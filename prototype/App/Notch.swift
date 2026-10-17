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
    private var tucked: [Tucked] = []
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
    /// 悬停不误触（LA-4，默认关）：停 0.12 秒且挪不到 8 点才展开、横扫不提示、提示只往下长 3 点、滚轮不算停留、
    /// » 在时只认点击、全屏时不因悬停展开。关着是旧样子：进来 0.12 秒就展开，提示两边各长 5 点。
    nonisolated static var hoverGuardEnabled: Bool {
        UserDefaults.standard.object(forKey: NotchHoverPolicy.defaultsKey) as? Bool ?? NotchHoverPolicy.defaultEnabled
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
            MainActor.assumeIsolated { self?.install() }
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
                self.leases.publishOngoing(ids, on: WS2.DisplayID(value: display))
                panel.setMinimalPresentation(minimal)
                panel.setActivities(values, selected: selected)
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
        activities.onDownloadsFinished = { [weak self] names in self?.away.noteDownloads(names) }
        away.tuckedCount = { [weak self] in self?.tuckedCount ?? 0 }
        away.windowIsCurrent = { [weak self] id in self?.owner.shaded[id] != nil }
        away.present = { [weak self] summary in self?.showAwaySummary(summary) }
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
        syncTimer?.tolerance = 0.5
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
        for screen in NSScreen.screens where Self.isEnabled {
            guard let id = Self.displayID(screen) else { continue }
            alive.insert(id)
            let slot = Self.slotRect(on: screen)
            let panel = panels[id] ?? NotchPanel(notch: slot.rect, virtual: slot.virtual)
            panels[id] = panel
            panel.yieldsToSystem = spaceGate.yielding.contains(id)
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
            panel.setActivities(activities.store.visible, selected: activities.store.selectedID)
            panel.setMusicArtwork(activities.nowPlayingArtwork)
            panel.onActivitySelect = { [weak self] id in self?.activities.select(id) }
            panel.onActivityAction = { [weak self] action in self?.activities.perform(action) }
            panel.onRowSeen = { [weak self] in self?.activities.rowSeen() }
            panel.canSwipeActivities = { [weak self] in self?.owner.launchpad.isShowing == false }
            panel.onHold = { [weak self, weak panel] in
                guard let self, let panel else { return false }
                return self.carPlayHold(on: panel)
            }
            panel.onLongPress = { [weak self, weak panel] in
                guard let self, let panel else { return }
                if self.activities.store.visible.isEmpty { self.owner.launchpad.navigate(to: .today) }
                else {
                    panel.expand(with: self.tiles())
                    self.requestThumbnails()
                    // 点（长按）打开的那一排接键盘，直接打字就筛（LA-7）；悬停打开的不接。
                    if panel.isExpanded, !panel.isFocusActive {
                        panel.beginFocus(pointerInside: panel.islandContains(NSEvent.mouseLocation), origin: .press)
                    }
                }
            }
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
                    self.tuckAll(on: center.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } })
                case .today: self.switchApp(back: true, panel: panel)
                case .library: self.switchApp(back: false, panel: panel)
                default: break
                }
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
                // 竖线右边的格子不是窗口，没有“看一眼”。
                if NotchRow.isOngoingID(id) { return }
                // 停在屏幕外的卷轴列不是收着的窗口，没有“看一眼”。
                if self?.stripReturn != nil, self?.owner.gestures.strips.allParkedIDs.contains(id) == true { return }
                if inside { self?.showPeek(id, tile: rect) } else { self?.endPeek() }
            }
            panel.onFocusKind = { [weak self] kind in self?.onShelfFocusKind?(kind) }
            panel.onMusicEarChange = { [weak self] in self?.syncAudioLevels() }
            panel.onAlertEnded = { [weak self] in self?.retryPendingPeek() }
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
        if !panels.isEmpty { DisplayShapes.shared.prepare { [weak self] in self?.applyShapes() } }
        // 先把两边的空位量好：第一次收进来时紧凑样式直接长成对的样子。
        for (display, panel) in panels { _ = room(for: panel, display: display) }
        configureFileDrag()
        refresh()
        syncAudioLevels()
        // 启动时不自我介绍、也不推荐“用 Rectangle 的快捷键”（docs/direction.md：没人问就不开口）。
        // 刘海能做什么，等他自己把指针停到刘海上时再说（hoverChanged）；Rectangle 那一套在设置 → 快捷键 → 更多排法。
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
        if panel.dropZone.contains(point) {
            panel.setDropState(.armed, choice: panel.choice(at: point))
        } else if near.contains(point) {
            panel.setDropState(.offered)
        } else {
            panel.setDropState(.none)
        }
    }

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
        panels.values.forEach { $0.setDropState(.none) }
    }

    /// 拖动结束：指针停在落点小岛的哪一格上，就去哪（收进刘海、半屏、铺满、魔法平铺）；不在岛上返回 nil。
    /// 收下时那一格变成对勾，停一下再收回（像面容 ID 通过时的那一下），别的屏上的落点直接收起。
    func dragEnded(at point: CGPoint) -> NotchPanel.DropChoice? {
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
    func release(_ id: CGWindowID, reason: String, from origin: NSRect? = nil) {
        endPeek()
        guard let index = tucked.firstIndex(where: { $0.id == id }) else { return }
        let item = tucked.remove(at: index)
        parkOnInstall.removeValue(forKey: id)
        changed.removeValue(forKey: id)
        wlog("notch: release id=\(id) reason=\(reason)")
        func collapseRow() {
            panels.values.forEach { $0.collapse() }
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
            if Motion.reduced {
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

    private func hoverChanged(_ inside: Bool, panel: NotchPanel) {
        guard !panel.isAuthenticating else { return }
        // 正拖着左段的一格出来放回卷轴：指针出了岛也不收，松手时再收（SS-04）。
        if !inside, draggingOutID != nil { return }
        // 概览里拖着一扇窗靠近刘海、落点正显示：不为悬停展开一排（算正在做的手势，SS-04）。
        if inside, panel.stripLanding { return }
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

    /// 点了（或按了 Return）竖线右边的某一格：音乐播放 / 暂停（这一排留着），其它都收起这一排再去（会话是“过去”）。
    private func activateOngoing(_ id: CGWindowID) {
        endPeek()
        if ongoingIDs.activityID(for: id) == NotchRow.fileShelfActivityID { openFileShelfCard(); return }
        guard let activityID = ongoingIDs.activityID(for: id),
              let cell = NotchRow.ongoingCells(from: activities.store.visible).first(where: { $0.activityID == activityID }),
              !cell.isEnded
        else { return }
        if cell.closesRow { panels.values.forEach { $0.collapse() } }
        activities.select(activityID)
        activities.perform(cell.action)
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
    func announce(_ text: String, detail: String = "", tone: NotchPanel.Tone = .info, symbol: String? = nil,
                  duration hold: TimeInterval? = nil, ear: String? = nil, speaks: Bool = true,
                  redEar: Bool = false, redIcon: Bool = false,
                  actionLabel: String? = nil, iconImage: NSImage? = nil,
                  onClick: (() -> Void)? = nil) -> Bool {
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
        let duration = hold ?? min(4.5, 1.8 + Double(text.count + detail.count) * 0.05)
        panel.alert(NotchPanel.Alert(id: 0, icon: icon, title: text, subtitle: detail, tone: tone, onClick: onClick ?? {}, ear: ear, earRed: redEar,
                                     actionLabel: actionLabel),
                    duration: duration)
        if speaks {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: detail.isEmpty ? text : "\(text)。\(detail)",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        wlog("notch: announce (\(tone)) \(text)\(detail.isEmpty ? "" : " — \(detail)")")
        return true
    }

    // MARK: 等刘海空下来再说

    /// 排队中的一句话。同一个 key 只留最新的；过期作废；优先级高的先说。
    private struct PendingAnnouncement {
        let key: String, text: String, detail: String, tone: NotchPanel.Tone, symbol: String?
        let priority: Int, expiresAt: TimeInterval
        let hold: TimeInterval?, onClick: (() -> Void)?
        var ear: String? = nil, speaks = true, redEar = false, redIcon = false
        var actionLabel: String? = nil, iconImage: NSImage? = nil
    }
    private var pendingAnnouncements: [PendingAnnouncement] = []
    private var pendingTimer: Timer?
    /// 锁屏、睡眠、换用户期间不说。排队的和已经挂在岛上的都收掉，解锁后不补播。
    private var announcementsHeld = false
    /// 这个队列最近说出的那一句（key 和标题）：它还在屏幕上时，同一个 key 的更新（比如电量到了）原位替换，
    /// 不排到后面再弹一次。屏幕上已经换成别人的话时不替换。
    private var shownAnnouncement: (key: String, title: String)?

    /// 和 announce 一样，但刘海正忙（展开、拖放、认证、正在说别的）时不放弃：按 key 合并、到期作废，
    /// 空下来后按优先级说（以前忙的时候直接丢掉）。返回值没有意义上的“失败”：要么现在说，要么排上了。
    func holdAnnouncements() {
        announcementsHeld = true
        peekTracker.cleared()
        pendingAnnouncements.removeAll()
        pendingTimer?.invalidate()
        pendingTimer = nil
        shownAnnouncement = nil
        for panel in panels.values { panel.dismissVisibleAlert(); panel.dismissPowerFlash() }
    }

    /// 电量那一下（只在没有别的提醒、持续活动时才出；撞上就不出）。
    @discardableResult
    func showPowerFlash(_ flash: PowerFlash) -> Bool {
        guard !announcementsHeld, Self.isEnabled, !Self.probeSilence, pendingAnnouncements.isEmpty,
              let panel = pointerPanel() else { return false }
        return panel.presentPowerFlash(flash)
    }

    /// 刘海上现在有没有别的东西：插电那一下用它判断“撞上就不出”。
    var isBusyForPowerFlash: Bool {
        guard let panel = pointerPanel() else { return true }
        return !pendingAnnouncements.isEmpty || panel.isBusyForPowerFlash
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
        pendingAnnouncements.removeAll { $0.key == key }
        if let shown = shownAnnouncement, shown.key == key, let panel = pointerPanel(), !panel.isAuthenticating,
           panel.alertForProbe?.title == shown.title,
           announce(text, detail: detail, tone: tone, symbol: symbol, duration: hold, ear: ear, speaks: speaks,
                    redEar: redEar, redIcon: redIcon, actionLabel: actionLabel, iconImage: iconImage, onClick: onClick) {
            shownAnnouncement = (key, text)
            return
        }
        let item = PendingAnnouncement(key: key, text: text, detail: detail, tone: tone, symbol: symbol,
                                       priority: priority, expiresAt: ProcessInfo.processInfo.systemUptime + ttl,
                                       hold: hold, onClick: onClick, ear: ear, speaks: speaks, redEar: redEar, redIcon: redIcon,
                                       actionLabel: actionLabel, iconImage: iconImage)
        if pendingAnnouncements.isEmpty, isFreeToAnnounce(),
           announce(text, detail: detail, tone: tone, symbol: symbol, duration: hold, ear: ear, speaks: speaks,
                    redEar: redEar, redIcon: redIcon, actionLabel: actionLabel, iconImage: iconImage, onClick: onClick) {
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

    /// 回来了：刘海说一句「离开期间」，停 8 秒收回。点一下，有收着的窗口就展开那一排，在那里看一眼、放回；
    /// 其余几项（设备、下载）点了不做什么。不补播，说过就清。
    fileprivate func showAwaySummary(_ summary: AwaySummary.Summary) {
        let opensRow = summary.firstWindowID.map { isTucked(CGWindowID($0)) } ?? false
        announceWhenFree(key: "away.summary", text: AwaySummary.heading, detail: summary.compactDetail,
                         symbol: "lock.open", priority: 5, ttl: 30, hold: AwaySummary.holdSeconds,
                         onClick: opensRow ? { [weak self] in
                             MainActor.assumeIsolated {
                                 guard let self, let panel = self.pointerPanel(), !panel.isExpanded, !self.tucked.isEmpty else { return }
                                 panel.expand(with: self.tiles())
                                 self.requestThumbnails()
                             }
                         } : nil)
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
            if announce(item.text, detail: item.detail, tone: item.tone, symbol: item.symbol,
                        duration: item.hold, ear: item.ear, speaks: item.speaks,
                        redEar: item.redEar, redIcon: item.redIcon,
                        actionLabel: item.actionLabel, iconImage: item.iconImage, onClick: item.onClick) {
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
        panels.values.compactMap { $0.alertForProbe }.first
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
            announce(WSL10n.text("notch.tuck.noWindows", zh: "这块屏上没有能收的窗口"), tone: .problem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
        for (display, panel) in panels { panel.yieldsToSystem = spaceGate.yielding.contains(display) }
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
        let windows = windowTiles()
        return Self.mergedRowEnabled ? windows + ongoingTiles() : windows
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

struct NotchTile {
    enum Kind {
        case tucked, strip, thumbnail, slideOver, carried, minimized, hiddenApp, elsewhere
        /// 竖线右边正在进行的格（M11）：编程会话、正在播放的、其它正在进行的事。
        case session, playing, activity
        /// 卷轴停在屏幕外的一列（SS-04）：左段收着的窗口后面，角上 ← 或 →，点一下把那一列滑进来。
        case parked

        var isOngoing: Bool {
            switch self {
            case .session, .playing, .activity: return true
            case .tucked, .strip, .thumbnail, .slideOver, .carried, .minimized, .hiddenApp, .elsewhere, .parked: return false
            }
        }
    }
    let id: CGWindowID
    let kind: Kind
    /// 格子上的画面。最小化、隐藏、别的桌面、侧拉的格子起初没有，后台截到后原地换上（NotchPanel.updateTileSnapshot）。
    var snapshot: CGImage?
    let icon: NSImage?
    var title: String
    var changed: Bool = false
    /// 别的桌面上的窗口：左上角写它在哪（“桌面 3”“全屏”）。
    var place: String? = nil
    /// 状态为“等你”的会话格：键盘焦点默认落在它上面（M07）。
    var waiting: Bool = false
    /// 正在进行的格（竖线右边）才有的内容。
    var ongoing: Ongoing? = nil
    /// 在那一排里打字筛选（LA-7）时，除标题以外还找的字：窗口格是 App 名，正在进行的格是种类名。
    /// 屏幕正在共享而被遮住的格不给（和标题一样不露）。
    var searchTerms: [String] = []
    /// 卷轴停在屏幕外的列才有（kind == .parked）。
    var parked: StripNotchExchange.ParkedCell? = nil

    struct Ongoing: Equatable {
        var activityID: String
        var subtitle: String
        var symbol: String
        var phase: NotchSessionPhase?
        var isPaused: Bool
        /// 这件事的量（M12）和它写出来的字（“42%”“第 2 / 9”）：和紧凑右耳同一套画法。
        var quantity: NotchActivity.Quantity = .unknown
        var quantityText: String? = nil
        /// 读屏念的整句（“项目，在等你”）。
        var spoken: String
        /// 点一下做什么，以及做完要不要收起这一排。
        var action: NotchActivityAction
        var closesRow: Bool
        /// 格子右下角的小键（音乐的播放 / 暂停，NP-4）：点它只做这件事，这一排留着。
        var accessory: NotchActivityAction? = nil
        /// 文件架这一格（FS-04）：叠几张缩略图；其它格是 nil。`shelfRevision` 变了说明缩略图换了，要重画。
        var shelfCount: Int? = nil
        var shelfRevision: Int = 0
        /// 过期（格子画 0.5 透明；读屏的整句里已有“可能已停”）和结束（最后的样子，没有能点的动作）。
        var isStale = false
        var isEnded = false
    }

    /// 屏幕正在共享时的样子：只剩 App 图标，没有画面、没有标题、没有“有变化”的点。
    func iconOnly() -> NotchTile {
        var copy = self
        copy.snapshot = nil
        copy.title = ""
        copy.changed = false
        copy.searchTerms = []
        return copy
    }

    /// 屏幕正在共享时，会话格不露项目名和做了什么：只剩“编程会话”和它的状态（读屏也一样）。
    func sessionRedacted() -> NotchTile {
        guard var copy = ongoing else { return self }
        var tile = self
        copy.subtitle = ""
        // 共享时只留会话状态；新加的额度数字不能绕过同一条遮隐路径。
        copy.quantity = .unknown
        copy.quantityText = nil
        let sessionKind = WSL10n.text("notch.kind.session", zh: "编程会话")
        let join = WSL10n.text("notch.join", zh: "，")
        switch copy.phase {
        case .waiting: copy.spoken = sessionKind + join + WSL10n.text("notch.row.waiting", zh: "在等你")
        case .running, .quota: copy.spoken = sessionKind + join + WSL10n.text("notch.row.running", zh: "在跑")
        case .quotaLow: copy.spoken = sessionKind + join + WSL10n.text("notch.row.runningQuotaLow", zh: "在跑，额度快用完了")
        default: copy.spoken = sessionKind
        }
        tile.title = WSL10n.text("notch.kind.session", zh: "编程会话")
        tile.ongoing = copy
        return tile
    }

    /// 内容变没变（比较用，不含画面）。
    var ongoingSignature: String? {
        // 量只记画法：数变了走 NotchPanel.updateOngoingQuantities（只改数字和环的终点），不整排重换。
        ongoing.map { "\($0.activityID)|\(title)|\($0.subtitle)|\($0.symbol)|\($0.phase.map(\.rawValue) ?? "")|\($0.isPaused)|\($0.spoken)|\($0.quantity.drawing)|\($0.shelfCount.map(String.init) ?? "")|\($0.shelfRevision)|\($0.isStale)|\($0.isEnded)" }
    }
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
            case .leftHalf: return WSL10n.text("say.preview.leftHalf", zh: "左半屏")
            case .fill: return WSL10n.text("say.preview.fillScreen", zh: "铺满屏幕")
            case .tuck: return WSL10n.text("silent.window.tuck", zh: "收进刘海")
            case .magic: return WSL10n.text("menu.magicTile", zh: "魔法平铺")
            case .rightHalf: return WSL10n.text("say.preview.rightHalf", zh: "右半屏")
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
    /// 有实时活动时，左右耳改成那一件本身：左耳是谁，右耳是数或进度。窗口个数退成一个点。
    struct Compact {
        enum ProgressTone { case accent, playback, focus, rest
            /// 计时器：橙色环，暂停时环和数字降到 0.5 并在环中画两道竖线（《日历、电量与计时器》稿）。
            case timer, timerPaused
            /// 日程：日历颜色的环；开始后能加入时是满环（右耳画绿色摄像机）。
            case calendar, calendarJoin }
        /// 进度怎么画：右耳一条细条，或者左耳一圈环（番茄钟）。
        enum ProgressStyle { case bar, ring }
        var pid: pid_t?
        var icon: NSImage?
        var count: Int
        var changed: Bool
        var leading: String? = nil
        var leadingSymbol: String? = nil
        var trailing: String? = nil
        /// 音量、亮度的 0…1，以及番茄钟左耳那圈环的进度。有值时画一条细条（番茄钟画环）。
        var progress: Double? = nil
        /// 实时活动的量（M12）：右耳画环加数、只写“第 k / n”、画转着的不确定弧，或什么都不画。
        var quantity: NotchActivity.Quantity = .unknown
        var progressTone: ProgressTone = .accent
        var progressStyle: ProgressStyle = .bar
        /// 窗口个数那颗信息点的颜色，跟着活动的语气走。
        var dotTone: NotchInfoDot.Tone = .accent
        /// 编程会话的这一步：右耳在跑画转圈、等你写橙色“等你”、做完画对勾。其它活动是 nil。
        var sessionPhase: NotchSessionPhase? = nil
        /// 音量、亮度、键盘灯的两耳（《音量与亮度》稿）：左耳符号、右耳白条，不写百分比。有值时左右耳都按它画。
        var level: LevelEar? = nil
        /// 正在播放的紧凑两耳（NP-2）：左耳封面、右耳 5 个静止取色点。nil = 今天的样子（歌名 + 符号 + 右耳的字）。
        var music: MusicEar? = nil
        /// 电量那一下（《日历、电量与计时器》稿）：左耳彩色符号、右耳同色百分比。有值时左右耳都按它画。
        var flash: PowerFlash? = nil
        /// 日程的两耳（CAL-3）：左耳日历色环加日历符号，右耳“4 分”；开始后能加入时右耳换成绿色摄像机。
        var calendar: NotchCalendarFace? = nil
        /// 文件架个数的两耳（左托盘符号、右个数）：读屏那一句。nil = 不是文件架。
        var shelfSpoken: String? = nil
        /// 过期（来源过了自己的过期时间还没消息）：两耳画 0.5 透明、右耳写“—”、读屏加“可能已停”。
        var stale = false
        func same(as other: Compact?) -> Bool {
            guard let other else { return false }
            return count == other.count && changed == other.changed && pid == other.pid
                && leading == other.leading && leadingSymbol == other.leadingSymbol && trailing == other.trailing
                && progress == other.progress && quantity == other.quantity && progressTone == other.progressTone
                && progressStyle == other.progressStyle && dotTone == other.dotTone && sessionPhase == other.sessionPhase
                && level == other.level && music == other.music && flash == other.flash && calendar == other.calendar
                && shelfSpoken == other.shelfSpoken
                && stale == other.stale
        }

        /// 版式相同（谁在左、什么语气）：曲名/进度数字可 content replace，不整岛淡出重建。
        func layoutSame(as other: Compact?) -> Bool {
            guard let other else { return false }
            return count == other.count && pid == other.pid
                && leadingSymbol == other.leadingSymbol && progressTone == other.progressTone
                && quantity.drawing == other.quantity.drawing
                && progressStyle == other.progressStyle && dotTone == other.dotTone
                && (leading == nil) == (other.leading == nil) && (sessionPhase == nil) == (other.sessionPhase == nil)
                // 两耳：同一种（音量、亮度、键盘灯）里数值、符号、拉长都原地换，条一格接一格地扫；换了一种才淡出淡入。
                && level?.kind == other.level?.kind && flash?.symbol == other.flash?.symbol && flash?.tone == other.flash?.tone
                && calendar?.joinable == other.calendar?.joinable && (shelfSpoken == nil) == (other.shelfSpoken == nil)
                // 暂停、换封面是原地换色，不整岛淡出重建；只有“是不是封面耳”变了才重建。
                && (music == nil) == (other.music == nil)
        }
    }

    /// 紧凑两耳放正在播放的：暂停与否、这首的封面（还没取到就是 nil，画占位）、读屏那一句。
    /// coverSide 由面板按主体宽、肩宽、刘海高算（`NowPlayingEars.coverSide`）；nil = 放不下，退回音符符号（今天的样子）。
    struct MusicEar: Equatable {
        var paused: Bool
        var artwork: NowPlayingArtworkImage?
        var spoken: String
        var coverSide: Double?
        static func == (a: MusicEar, b: MusicEar) -> Bool {
            a.paused == b.paused && a.spoken == b.spoken && a.coverSide == b.coverSide
                && a.artwork?.trackKey == b.artwork?.trackKey && a.artwork?.fingerprint == b.artwork?.fingerprint
        }
    }

    enum LevelKind {
        case volume, brightness, keyboardLight

        var coreKind: NotchLevelKind {
            switch self {
            case .volume: return .volume
            case .brightness: return .brightness
            case .keyboardLight: return .keyboardLight
            }
        }
    }

    /// 这一刻两耳要画什么：数值、符号（已按分档和设备选好）、到头的拉长、读屏那一句。
    struct LevelEar: Equatable {
        var kind: LevelKind
        var value: Double
        var symbol: String
        /// 键盘灯熄灭：符号画暗。
        var dimmed: Bool
        var stretch: NotchLevelStep.Stretch?
        /// 这一下按在哪一头上（数值没变）；平常的一下是 nil。
        var edge: NotchLevelStep.Edge?
        /// 到头再按的次数；变了，减少动态效果下条的那一头亮一下。
        var edgePushes: Int
        var spoken: String
    }

    struct Level {
        var kind: LevelKind
        var value: Double
        var muted = false
        var output: NotchLevelEars.Output = .speaker
        var stretch: NotchLevelStep.Stretch?
        var edge: NotchLevelStep.Edge?
        var edgePushes = 0

        var ear: LevelEar {
            let tier = NotchLevelStep.tier(kind: kind.coreKind, value: value, muted: muted)
            return LevelEar(kind: kind, value: value,
                            symbol: NotchLevelEars.symbolName(kind: kind.coreKind, value: value, muted: muted, output: output),
                            dimmed: tier.isDimmed, stretch: stretch, edge: edge, edgePushes: edgePushes,
                            spoken: NotchLevelEars.spokenText(kind: kind.coreKind, value: value, muted: muted))
        }
    }

    /// 探针：Alcove 或同类音量提示在不在。nil 时看正在运行的 App。
    static var foreignHUDOverride: Bool?
    static func foreignHUDIsRunning() -> Bool {
        if let foreignHUDOverride { return foreignHUDOverride }
        return NSWorkspace.shared.runningApplications.contains { app in
            let name = (app.localizedName ?? "").lowercased()
            let id = (app.bundleIdentifier ?? "").lowercased()
            if id.hasPrefix("com.apple.") { return false }
            return name == "alcove" || name == "mediamate" || id.contains("alcove") || id.contains("mediamate")
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
        /// 右边的等宽大数字（离开就锁的倒数）。每秒原地换，宽度不跳。
        var ear: String? = nil
        /// 右耳的数字用红色（电量 20% 及以下）。
        var earRed = false
        /// 右边的绿色按钮字（日程的“加入”）。整条提醒仍然可点，点哪里都是同一件事；按钮只是告诉人点下去会发生什么。
        var actionLabel: String? = nil
        /// 换歌一瞥（NP-3）：不为 nil 时是低矮的一行“歌名 + 歌手”，不画图标和副句。
        var peek: PeekLine? = nil
    }

    /// 换歌一瞥那一行的字。歌手的颜色取自封面（`ArtworkPalette.text`），还没取到就是白 0.6 的副句色。
    struct PeekLine: Equatable {
        var title: String
        var artist: String
        var artistColor: NSColor?
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
    /// 无刘海胶囊优先圆角（机型顶角 pt）；nil 则用高度一半。
    var capsuleCorner: CGFloat? {
        didSet {
            guard capsuleCorner != oldValue else { return }
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
    var onTileAccessory: ((CGWindowID) -> Void)?
    /// 点刘海（不在某一格上）：点了几下、刘海在屏幕上的位置。
    var onPress: ((Int, NSRect) -> Void)?
    /// 拖着文件停在刘海上（或者丢进刘海）。
    var onFiles: (([URL], NSRect) -> Void)?
    /// FS-03：文件那一种落点小岛上松手。松在哪、会发生什么由小岛算好；返回 false 就是没收（东西飞回原处）。
    var onFileDrop: ((FileDropRelease, NSPasteboard) -> Bool)?
    /// FS-03：停在“用 App 打开”上够久（今天的 0.35 秒）。
    var onFileDropDwell: (() -> Void)?
    var onActivitySelect: ((String) -> Void)?
    var onActivityAction: ((NotchActivityAction) -> Void)?
    var canSwipeActivities: (() -> Bool)?
    /// 那一排收起时，里面摆过结束了的活动：看过了，控制器据此调 `rowSeen()`。
    var onRowSeen: (() -> Void)?
    var onLongPress: (() -> Void)?
    /// 真正的长按（不含智能展开、右键菜单）先问这里：返回 true 表示已处理，不再走 onLongPress。CarPlay 全屏开着时用。
    var onHold: (() -> Bool)?
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
            endFocus()
            alertTimer?.invalidate(); alertInfo = nil
            suspendedTiles = nil
            guard isExpanded else { return }
            isExpanded = false; tiles = []
            updateVisibility(); apply(animated: false)
        case .authorization:
            canvas.resetInteractions()
            authenticationView = nil
            canvas.setAuthentication(nil)
            updateVisibility(); apply(animated: false)
        case .launchpad, .windowBrowser, .conductor, .pomodoro, .nowPlaying, .agentReview,
             .ownedCodex, .ownedModelPicker, .silent:
            break
        }
    }
    private var meter: Level?
    /// 电量那一下：紧凑大小里亮 2.6 秒（`PowerFlashPolicy.holdSeconds`）。
    private var powerFlashState: PowerFlash?
    private var powerFlashTimer: Timer?
    private var levelTimer: Timer?
    /// 最后一下之后 0.5 秒念一次“音量 45%”，不逐格念。
    private var levelAnnounce: DispatchWorkItem?
    /// 到头再按的次数（连续往同一头顶才累加）。
    private var levelEdges = NotchLevelStep.EdgeCounter()
    /// 全屏桌面上两耳已确认看得见：让开着的面板也露出来，直到两耳收回。
    private(set) var levelYieldOpen = false
    private(set) var yieldedHUD = false
    private var companionText: String?
    private(set) var isSplit = false
    private var suspendedTiles: [NotchTile]?
    /// 最近一次展开有没有播进场。挂起后接回来是 false。
    private(set) var lastShelfChangeAnimated = true
    private(set) var showsSecondaryDot = false
    private var activityItems: [NotchActivity] = []
    /// 展开时的活动卡只放真正的活动：文件架个数只在紧凑两耳上露（《文件架》稿），不进卡、不进最小形。
    private var cardItems: [NotchActivity] { activityItems.filter { !$0.kind.isShelf } }
    private var activitySelection: String?
    private var authenticationView: (NSView & NotchInteractiveContent)?
    var isAuthenticating: Bool { authenticationView != nil }
    func isShowingInteraction(_ view: NSView) -> Bool { authenticationView === view }
    /// 内容自己报要多大；不报的照旧的 344×68。
    private var interactionSize: NSSize {
        (authenticationView as? any WS2LeaseContent)?.interactionSize ?? NSSize(width: 344, height: 68)
    }
    func setAuthentication(_ view: NotchAuthenticationView?, animated: Bool = true) {
        setInteraction(view, animated: animated)
    }
    func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {
        canvas.resetInteractions()
        pressWork?.cancel(); pressWork = nil
        hoverTimer?.invalidate(); hinting = false; pulled = 0
        _ = hoverPolicy.exit(); hoverGuarded = false
        alertTimer?.invalidate(); alertInfo = nil; dropState = .none; stripLanding = false
        authenticationView = view
        canvas.setAuthentication(view)
        updateVisibility(); apply(animated: animated)
    }
    func setActivities(_ items: [NotchActivity], selected: String?) {
        guard activityItems != items || activitySelection != selected else { return }
        let changedShape = activityItems.isEmpty != items.isEmpty
        // 最小呈现开着：谁是紧凑、谁退成最小变了（点最小形互换、有活动来去），最小形走弹簧挪；关着一概不动。
        let minimalChanged = minimalPresentation
            && minimalLayoutIDs(activityItems, activitySelection) != minimalLayoutIDs(Array(items.prefix(3)), selected)
        activityItems = Array(items.prefix(3)); activitySelection = selected
        updateVisibility()
        apply(animated: changedShape || minimalChanged)
    }

    /// 正在播放的这首的封面（NP-2）。由 NotchController 在换曲取到、换掉、丢掉时推过来；只在紧凑两耳里用，内存里只此一张。
    private(set) var musicArtwork: NowPlayingArtworkImage?
    func setMusicArtwork(_ image: NowPlayingArtworkImage?) {
        guard musicArtwork?.trackKey != image?.trackKey || musicArtwork?.fingerprint != image?.fingerprint else { return }
        musicArtwork = image
        // 换歌一瞥还挂着：歌手那一截换成新封面的字色（原地换色，不动计时和形状）。
        if var peek = alertInfo?.peek {
            peek.artistColor = image.map {
                NSColor(srgbRed: $0.palette.text.r, green: $0.palette.text.g, blue: $0.palette.text.b, alpha: 1)
            }
            alertInfo?.peek = peek
            apply(animated: false)
        }
        // 只有此刻画着音乐两耳才需要重排；原地换封面和取色，不动形状。
        guard displayCompact()?.music != nil else { return }
        apply(animated: false)
    }

    /// 紧凑的封面耳此刻画着（NP-6：只在它露着时录声音）。变了叫 onMusicEarChange。
    private(set) var showsMusicEar = false
    var onMusicEarChange: (() -> Void)?
    /// 右耳 5 根的样子（NP-6）：由 NotchController 推过来；跟着声音跳时每秒 30 次。只改那 5 个图层，不重排。
    func setMusicWave(_ wave: NowPlayingWave) { canvas.setMusicWave(wave) }

    /// 点紧凑左耳或右耳（NP-2 留的钩子，NP-4 接上）：长成正在播放大卡。没接上（nil）或这一下开不了（没有在放的歌、锁屏）= 点刘海的行为，一点不变。
    var nowPlayingCardOpener: (() -> Bool)?
    func openNowPlayingCard() {
        if nowPlayingCardOpener?() == true { return }
        pressed(1)
    }

    /// 大卡长在这块屏的刘海上要知道的：刘海的大小、有没有硬件刘海、点没点在岛上、紧凑左耳此刻画着封面。
    func nowPlayingCardHost() -> NowPlayingCardHost {
        NowPlayingCardHost(
            notch: NowPlayingCard.NotchGeometry(width: notch.width, height: notch.height, virtual: isVirtual),
            islandContains: { [weak self] point in self?.islandContains(point) ?? false },
            interactionSizeChanged: { [weak self] opening in
                MainActor.assumeIsolated { self?.interactionSizeChanged(opening: opening) }
            },
            earCoverVisible: !isVirtual && displayCompact()?.music != nil && musicArtwork != nil)
    }

    /// 卡的高度变了（输出设备列表开、收）：岛按新高度长。开用 expand，收用 calm（稿）。
    func interactionSizeChanged(opening: Bool) {
        guard isAuthenticating else { return }
        let token = opening ? Motion.Spring.expand : Motion.Spring.calm
        apply(animated: true, spring: NotchCanvasView.Spring(response: token.response, bounce: token.bounce))
    }

    /// 最小呈现（M13）：开着才有最小形，也才多量一段菜单栏空位。由 NotchController 按 defaults 推过来。
    private(set) var minimalPresentation = false
    func setMinimalPresentation(_ on: Bool) {
        guard on != minimalPresentation else { return }
        minimalPresentation = on
        apply(animated: false)
    }
    /// 无刘海胶囊落在菜单栏下方（R02）：由 NotchController 按 defaults 推过来；真刘海屏上不起作用。
    private(set) var capsuleBelowMenuBar = false
    func setCapsuleBelowMenuBar(_ on: Bool) {
        guard on != capsuleBelowMenuBar else { return }
        capsuleBelowMenuBar = on
        if isVirtual { apply(animated: false) }
    }
    private func minimalLayoutIDs(_ items: [NotchActivity], _ selected: String?) -> [String] {
        let layout = NotchMinimalPresentation.layout(items: items, selected: selected, enabled: true)
        return [layout.compact?.id ?? ""] + layout.minimum.map(\.id)
    }
    private var pressWork: DispatchWorkItem?
    /// 现在有没有东西能往下拉出来（收进刘海的窗、收在屏幕边的侧拉）。
    var canPull: (() -> Bool)?
    private(set) var isExpanded = false
    /// 指针刚停上来、还没展开：岛先往外长一点点，告诉人“这里能展开”（WWDC18：顺着手势方向给提示、别等计时器）。
    private var hinting = false
    /// 悬停不误触（LA-4）：这一趟进来时开关开着，就由 NotchHoverPolicy 决定提示和展开；关着走原来的计时器。
    private var hoverGuarded = false
    private var hoverPolicy = NotchHoverPolicy()
    /// 系统的 » 在（图标太多被藏起来）：悬停只认点击。量菜单栏的人（LA-0 / NotchWatch）知道了再设；没人设就当不在。
    var menuBarOverflowShown = false
    /// 两指往下拉了多少（点）。
    private var pulled: CGFloat = 0
    private(set) var dropState: DropState = .none
    private(set) var dropChoice: DropChoice = .tuck
    /// SS-04：概览里拖着一扇窗靠近刘海，刘海长成 340 × 84 的落点（写“松手收进刘海”）。用 dropState = .offered 占位，
    /// 所以提醒、悬停展开、最小形都按“落点进行中”让开；放行占着刘海时不出（setStripLanding 里挡）。
    private(set) var stripLanding = false
    /// FS-03：正在拖文件、文字、图片或链接（不是拖窗口）。nil 就是没有；落点小岛画三格。
    private(set) var fileDrop: FileDropIslandModel?
    private var fileDwell: Timer?
    private var compact: Compact?
    /// 刘海两边的菜单栏空不空：两边都空着，紧凑样式放在刘海左右；有一边占着就放在刘海下面（下巴）。
    /// nil 是还没量出来：先不露面，最多等 0.35 秒，还不知道就当占着。
    private var room: MenuBarRoom.Sides?
    private var roomWaitOver = false
    private var roomTimer: Timer?
    private var alertInfo: Alert? {
        didSet {
            guard oldValue != nil, alertInfo == nil else { return }
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onAlertEnded?() } }
        }
    }
    private var alertTimer: Timer?
    var isAlerting: Bool { alertInfo != nil }
    /// 挂着的提醒收了（到点、被点掉、被别的顶掉）：排在后面的东西据此再看一眼（NP36）。下一轮主队列再叫，免得在收的半路上改状态。
    var onAlertEnded: (() -> Void)?
    /// 正挂着的是换歌一瞥（NP-3）。
    var isShowingPeek: Bool { alertInfo?.peek != nil }
    /// 一瞥正挂着就收掉（播放器退出了）。别的提醒不动。
    func dismissPeek() {
        guard isShowingPeek else { return }
        dismissVisibleAlert()
    }
    /// 当前这句提醒挂上岛的时刻（卡住提示按对时判断形状长没长完）。
    private var alertShownAt: CFTimeInterval = 0
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

    /// 正在拖的那扇窗的最小尺寸；nil 按 200×150。
    var dragMinimumSize: CGSize?

    /// 这一格去了窗口放不下（目标比窗口的最小尺寸还小）就灰掉。收进刘海、魔法平铺不改成固定大小，永远可用。
    func isDisabled(_ choice: DropChoice) -> Bool {
        let visible = NSScreen.screens.first { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }?.visibleFrame
        guard let visible else { return false }
        let target: CGSize?
        switch choice {
        case .leftHalf, .rightHalf: target = CGSize(width: visible.width / 2, height: visible.height)
        case .fill: target = visible.size
        case .tuck, .magic: target = nil
        }
        return NotchSmallBehaviour.isDisabled(target: target, minimum: dragMinimumSize)
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
        canvas.onTileAccessory = { [weak self] id in self?.onTileAccessory?(id) }
        canvas.onActivitySelect = { [weak self] id in self?.onActivitySelect?(id) }
        canvas.onActivityAction = { [weak self] action in self?.onActivityAction?(action) }
        canvas.canSwipeActivities = { [weak self] in self?.canSwipeActivities?() ?? false }
        canvas.onLongPress = { [weak self] in
            guard let self else { return }
            if self.onHold?() == true { return }
            self.onLongPress?()
        }
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
        canvas.onNowPlayingEar = { [weak self] in self?.openNowPlayingCard() }
        canvas.onFiles = { [weak self] files in
            guard let self else { return }
            self.onFiles?(files, self.notch)
        }
        canvas.registerForDraggedTypes([.fileURL])
        canvas.onIslandDrag = { [weak self] info, phase in self?.islandDrag(info, phase) ?? [] }
        canvas.onPointerMoved = { [weak self] in
            guard let self else { return }
            guard self.enterDeferred else { self.hoverMoved(); return }
            self.pointerWhenGrown = nil
            self.hover(true)
        }
        canvas.onScrollNoise = { [weak self] in self?.hoverScrolled() }
        apply(animated: false)
        updateVisibility()
    }

    private func showActivityMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let destinations: [(String, String)] = [
            (WSL10n.text("settings.shade.activities.name", zh: "实时活动"), "today"),
            (WSL10n.text("notch.kind.music", zh: "音乐"), "enableMusic"),
            (WSL10n.text("silent.activity.airdrop", zh: "隔空投送"), "airDrop"),
            (WSL10n.text("silent.activity.route", zh: "路线"), "route"),
            (WSL10n.text("notch.kind.voiceMemos", zh: "语音备忘录"), "voiceMemos"),
            (WSL10n.text("settings.shade.focus.name", zh: "番茄钟"), "focusOpen")]
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

    /// 认证卡要输入；键盘焦点模式（M07）里方向键、Return、Esc 也要送到这里。
    override var canBecomeKey: Bool { isAuthenticating || focus.isActive }
    /// 文件架卡开着时面板要能成为主窗口：大图预览（QLPreviewPanel）顺着主窗口的响应链找到那一页。
    override var canBecomeMain: Bool { authenticationView is FileShelfView }
    /// 文件架卡要知道刘海那一条有多高、有没有：真刘海时左右耳画在那一条里。
    var cardStrip: (hasNotch: Bool, height: CGFloat) { (!isVirtual, notch.height) }

    // MARK: 键盘焦点（M07）

    /// 刘海那一排的焦点状态机（纯逻辑，见 NotchFocusController）。
    private(set) var focus = NotchFocusController()
    /// 面板为键盘焦点接过 key（交还时才要让一下）。
    private var heldKey = false
    var isFocusActive: Bool { focus.isActive }

    private func focusCells() -> [NotchFocusController.Cell] {
        tiles.map {
            NotchFocusController.Cell(id: $0.id, title: $0.title, waiting: $0.waiting, tucked: $0.kind == .tucked,
                                      ongoing: $0.kind.isOngoing, session: $0.kind == .session, spoken: $0.ongoing?.spoken,
                                      terms: $0.searchTerms)
        }
    }

    /// 在那一排里打字筛选（LA-7）时还留着的格子；没有筛选是 nil（所有格子）。`tiles` 始终是完整的一排。
    private var filterIDs: Set<CGWindowID>?
    /// 现在显示的格子（筛选之后）。
    private var shownTiles: [NotchTile] {
        guard let filterIDs else { return tiles }
        return tiles.filter { filterIDs.contains($0.id) }
    }
    /// 按状态机里的筛选结果更新留着的格子：没有筛选字就是 nil。
    private func syncFilter() {
        filterIDs = focus.isActive && focus.isFiltering ? Set(focus.visibleIDs) : nil
    }

    /// 焦点落在会话格还是窗口格（遥控器 M09 要知道）。变了才告诉。
    var onFocusKind: ((RemoteLayerHost.Focus) -> Void)?
    private var reportedFocusKind = RemoteLayerHost.Focus.window
    private func reportFocusKind() {
        let kind: RemoteLayerHost.Focus = focus.focusIsOnSession ? .session : .window
        guard kind != reportedFocusKind else { return }
        reportedFocusKind = kind
        onFocusKind?(kind)
    }

    /// 岛此刻在屏幕上的外框（含动画中）；还没画出来就用刘海。
    func islandContains(_ point: NSPoint) -> Bool {
        (canvas.islandOnScreen(panelOrigin: frame.origin) ?? notch).contains(point)
    }

    /// 那一排已经展开着：从默认那一格开始，面板临时接键盘。指针这时在刘海里，焦点先藏着，交给指针。
    @discardableResult
    func beginFocus(pointerInside: Bool, origin: NotchFocusController.Origin = .shortcut) -> Bool {
        // 悬停打开的那一排不接键盘：你在别的 App 里打字，不会被刘海吃掉。
        guard origin != .hover, isExpanded, !tiles.isEmpty, !isAuthenticating, !focus.isActive else { return false }
        focus.setCells(focusCells())
        if pointerInside { focus.pointerEntered() } else { focus.pointerLeft() }
        return applyFocus(focus.begin(origin: origin))
    }

    /// 方向、Return、Esc、展开动作的统一出口（键盘、遥控器、手柄都从 NotchController.perform 进来）。返回有没有处理。
    @discardableResult
    func performFocus(_ action: WS2.Action) -> Bool {
        guard !isAuthenticating, NotchFocusController.handles(action) else { return false }
        return applyFocus(focus.handle(action))
    }

    /// 焦点回到最前面那一格（遥控器用）。返回焦点有没有动。
    @discardableResult
    func focusFirstCell() -> Bool {
        guard !isAuthenticating else { return false }
        return applyFocus(focus.focusFirst())
    }

    private func applyFocus(_ effect: NotchFocusController.Effect) -> Bool {
        switch effect {
        case .none:
            return false
        case .begin(let line):
            heldKey = true
            makeKey()
            canvas.setTileFocus(focus.visibleFocusID, animated: false)
            var spoken = line
            if let position = focus.focusedPosition, let cell = focus.focusedCell {
                spoken += "。" + NotchFocusController.moveAnnouncement(cell: cell, index: position, count: focus.cells.count)
            }
            announceFocus(spoken)
            reportFocusKind()
            wlog("notch: focus begin cells=\(focus.cells.count)")
        case .moved(let id, let line):
            canvas.setTileFocus(id)
            announceFocus(line)
            reportFocusKind()
        case .bump(let direction, let line):
            canvas.setTileFocus(focus.focusedID, bump: direction)
            announceFocus(line)
        case .filtered(let line):
            // 筛选的字变了（打字、退格、Esc 清字）：对不上的格子离开，剩下的并拢，焦点落第一格。
            syncFilter()
            canvas.setTileFocus(focus.visibleFocusID, animated: false)
            apply(animated: true)
            announceFocus(line)
            reportFocusKind()
        case .activate(let id):
            // 和指针点一下同一条路：onTileClicked → NotchController.open（放回、去、还原，flyOut 弹簧），之后这一排收起。
            if !canvas.activateTile(id) { onTileClicked?(id, nil) }
        case .end:
            wlog("notch: focus end")
            collapse()
        }
        return true
    }

    private func announceFocus(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// 指针进出刘海：进来焦点就隐藏、交给指针；出去时那一排随即收起（hoverChanged），焦点跟着结束。
    private func focusPointer(_ inside: Bool) {
        if inside { focus.pointerEntered() } else { focus.pointerLeft() }
        if focus.isActive { canvas.setTileFocus(focus.visibleFocusID) }
        // 遥控器连着时，指针进出刘海立刻让位或收回（没连着时这里是空的）。
        GlobalInputFilter.onPointerInNotch?(inside)
    }

    /// 那一排要收起或被挂起：焦点结束，键盘交还。必须赶在 isExpanded 变 false 之前，面板还在屏幕上。
    private func endFocus() {
        // 状态机可能已经先结束了（Esc / 再按展开动作），但面板还握着键盘：以“握着”为准。
        guard focus.isActive || heldKey else { return }
        heldKey = false
        focus.shelfClosed()
        filterIDs = nil
        reportFocusKind()
        canvas.setTileFocus(nil, animated: false)
        // 面板是不抢前台的：它当过 key，就让一下，键盘回到原来的 App。
        if isKeyWindow {
            orderOut(nil)
            updateVisibility()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard focus.isActive else { super.keyDown(with: event); return }
        let command = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if let action = NotchFocusController.action(forKeyCode: event.keyCode, hasCommandModifiers: command) {
            performFocus(action)
        } else if let input = NotchFocusController.typedInput(forKeyCode: event.keyCode, characters: event.characters,
                                                              hasCommandModifiers: command) {
            // 直接打字就筛（LA-7）；悬停打开的那一排不会走到这里（面板根本没接键盘）。
            _ = applyFocus(focus.apply(input))
        }
        // 焦点模式里别的键吞掉，不让系统“嘟”一声。
    }

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
            // 提醒收起之前先量好图标在屏幕上的位置：窗口从那里起飞。
            let icon = alert.id != 0 ? NotchSmallBehaviour.flightOrigin(icon: canvas.alertIconScreenRect) : nil
            alertTimer?.invalidate()
            alertInfo = nil
            apply(animated: true)
            if let onClick = alert.onClick { onClick() } else if alert.id != 0 { onTileClicked?(alert.id, icon) }
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

    /// 这块屏是原生全屏桌面或调度中心开着：紧凑、提醒、展开、最小一律不画。第 1 层（授权放行、离开就锁倒数）照常出现。
    var yieldsToSystem = false {
        didSet {
            guard yieldsToSystem != oldValue else { return }
            updateVisibility()
        }
    }

    private func updateVisibility() {
        if yieldsToSystem, !isAuthenticating, !levelYieldOpen {
            if isVisible { orderOut(nil) }
            return
        }
        let needed = isAuthenticating || !isVirtual || compact != nil || dropState != .none || isExpanded
            || alertInfo != nil || !activityItems.isEmpty || meter != nil || powerFlashState != nil || companionText != nil || showsSecondaryDot
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
        // 由规则给（NotchRoomPolicy，LA-3）：最宽 34，否则按量到的窄的那边，和以前算得一样。
        NotchRoomPolicy.earWidth(leading: room?.leading, trailing: room?.trailing)
    }

    /// 紧凑样式要量的两段：真刘海是刘海左右各往外 34 点，隐形刘海是那颗小胶囊的左右两半（从正中往外 40 点）。
    var compactSpans: (leadingEdge: CGFloat, trailingEdge: CGFloat, reach: CGFloat) {
        // 最小呈现开着：多量几颗最小形要的那一段（量得更远不改 sideWidth：它仍最宽 34）；关着照旧。
        if isVirtual { return (notch.midX, notch.midX, minimalPresentation ? NotchMinimalPresentation.measuredReach(for: .capsule) : 40) }
        return (notch.minX, notch.maxX, minimalPresentation ? NotchMinimalPresentation.measuredReach(for: .notched) : Self.sideWidth)
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

    /// 锁屏时把已经挂在岛上的那句收掉，不留到解锁后再说。
    func dismissVisibleAlert() {
        alertTimer?.invalidate()
        alertTimer = nil
        guard alertInfo != nil else { return }
        alertInfo = nil
        apply(animated: false)
    }

    /// 提醒：短暂展开说一句，2.6 秒后收回。
    /// 那一排已经打开、正在认证或落点进行时，不插进这句，只留一个点，以后也不重播。
    /// 正在播放、岛还没收成一排时，这句话分到旁边那颗岛上，播完再合并。
    /// 提醒：短暂展开说一句，`alert.hold` 后收回（指针停在上面时展开的是一排，不插提醒）。
    func alert(_ info: Alert, duration: TimeInterval = Motion.Hold.alert) {
        // 你正在按音量亮度键（交互层）：这一句变成一个点并消耗掉，不回来补说。
        if meter != nil, !isAuthenticating {
            if let leases, let displayID { _ = leases.remind(on: displayID) }
            showsSecondaryDot = true
            apply(animated: false)
            return
        }
        let blocked = isAuthenticating || isExpanded || dropState != .none
        if blocked {
            if let leases, let displayID { _ = leases.remind(on: displayID) }
            pullSecondaryDot()
            return
        }
        if let leases, let displayID, !leases.remind(on: displayID) {
            pullSecondaryDot()
            return
        }
        // 开关关着：撞上正在播放就分出第二颗岛（现状）；开着：不出第二颗，落到下面这一颗岛 bloom 成提醒，
        // 提醒结束后 `apply` 回到媒体紧凑。
        if info.peek == nil, NotchMinimalPresentation.alertPlan(hasActivities: !activityItems.isEmpty, meterShowing: meter != nil,
                                                                enabled: minimalPresentation) == .split {
            split(showing: info.title)
            alertTimer?.invalidate()
            alertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.mergeSplit() }
            }
            return
        }
        if powerFlashState != nil { powerFlashTimer?.invalidate(); powerFlashTimer = nil; powerFlashState = nil }
        alertInfo = info
        alertShownAt = CACurrentMediaTime()
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

    /// 卡住提示挂着时他按对了那一下（CoachEcho 定怎么办）：键帽回声后 0.15 秒收回，形状还在长就直接收回。
    func echoHabitAlert(sameRule: Bool, byUser: Bool, quiet: Bool) {
        let showing = alertInfo?.demo == .habit && !isExpanded
        let plan = CoachEcho.plan(showingHabitTip: showing, sameRule: sameRule, byUser: byUser, quiet: quiet,
                                  elapsed: CACurrentMediaTime() - alertShownAt,
                                  reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        func retract() {
            alertTimer?.invalidate()
            alertTimer = nil
            alertInfo = nil
            apply(animated: true)
        }
        switch plan {
        case .none: return
        case .retractNow: retract()
        case let .echo(_, after):
            canvas.echoAlertKeys()
            alertTimer?.invalidate()
            let timer = Timer(timeInterval: after, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, self.alertInfo?.demo == .habit else { return }; self.alertInfo = nil; self.apply(animated: true) }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            alertTimer = timer
        }
    }

    private func pullSecondaryDot() {
        let dot = displayID.flatMap { leases?.snapshot($0)?.hasSecondaryDot } ?? false
        guard dot != showsSecondaryDot else { return }
        showsSecondaryDot = dot
        apply(animated: false)
    }

    /// 更高的层进来：那一排从画面上拿掉，格子留着。
    @discardableResult
    func suspendShelf() -> Bool {
        guard isExpanded else { return false }
        endFocus()
        suspendedTiles = tiles
        isExpanded = false
        updateVisibility()
        apply(animated: false)
        return true
    }

    /// 让出之后接回挂起的那一排。不重播展开。
    func resumeSuspendedShelf() {
        guard let saved = suspendedTiles else { return }
        suspendedTiles = nil
        expand(with: saved, merged: mergedRow, animated: false)
        if !isExpanded { suspendedTiles = saved }
    }

    /// 音量、亮度、键盘灯的两耳（《音量与亮度》稿）。对方的提示在跑就让位。
    /// muted：静音（符号是斜线喇叭）；output：声音从哪出（AirPods、耳机换设备符号）；
    /// edge：这一下按在头上、数值没变（条拉长，再弹回）；nil 就是平常的一下。
    func presentLevel(_ kind: LevelKind, value: Double, muted: Bool = false, output: NotchLevelEars.Output = .speaker,
                      edge: NotchLevelStep.Edge? = nil) {
        guard !isAuthenticating else { return }
        if Self.foreignHUDIsRunning() {
            yieldedHUD = true
            return
        }
        yieldedHUD = false
        if powerFlashState != nil { powerFlashTimer?.invalidate(); powerFlashTimer = nil; powerFlashState = nil }
        let clamped = NotchLevelStep.clamp(value)
        // 到头再按：往同一头顶的次数；平常的一下清零，条弹回。减少动态效果不拉长，只亮一下。
        let pushes = levelEdges.record(
            NotchLevelStep.Result(value: clamped, edge: edge, unmutes: false, changed: false),
            at: ProcessInfo.processInfo.systemUptime)
        let stretch = edge.flatMap { Motion.reduced ? nil : NotchLevelStep.stretch(edge: $0, pushes: pushes) }
        // 音量亮度是你手上正在按的（交互层）：正在说的短暂提醒变成一个点，不回来补说。
        if alertInfo != nil {
            alertTimer?.invalidate()
            alertTimer = nil
            alertInfo = nil
            showsSecondaryDot = true
        }
        meter = Level(kind: kind, value: clamped, muted: muted, output: output, stretch: stretch, edge: edge,
                      edgePushes: pushes)
        updateVisibility()
        apply(animated: true)
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: Motion.Hold.level, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retireLevel() }
        }
        scheduleLevelAnnouncement()
    }

    /// 按住的键松开了：顶在头上的条弹回（还没松手时一直顶着）。
    func levelKeyReleased() {
        guard var current = meter, current.stretch != nil else { return }
        current.stretch = nil
        current.edge = nil
        meter = current
        levelEdges.reset()
        apply(animated: true)
    }

    /// 电量那一下现在不该出：刘海正忙（展开、认证、拖放、提醒、音量亮度、有持续活动、两耳放不下）或已有一下在亮。
    /// 它是最低一类短暂提醒，撞上就不出，也不排队补播。
    var isBusyForPowerFlash: Bool {
        isAuthenticating || isExpanded || dropState != .none || alertInfo != nil || meter != nil
            || companionText != nil || !activityItems.isEmpty || powerFlashState != nil
            || isVirtual || compactShape != .sides
    }

    /// 电量那一下：settle 长出两耳（宽 刘海+68、高同刘海），停 2.6 秒，calm 收回。返回有没有出。
    @discardableResult
    func presentPowerFlash(_ flash: PowerFlash) -> Bool {
        guard !isBusyForPowerFlash else { return false }
        if let leases, let displayID, !leases.remind(on: displayID) { return false }
        powerFlashState = flash
        updateVisibility()
        apply(animated: true, spring: NotchCanvasView.Spring(response: Motion.Spring.settle.response, bounce: Motion.Spring.settle.bounce))
        powerFlashTimer?.invalidate()
        let timer = Timer(timeInterval: PowerFlashPolicy.holdSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPowerFlash() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        powerFlashTimer = timer
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: flash.spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    func dismissPowerFlash() {
        powerFlashTimer?.invalidate()
        powerFlashTimer = nil
        guard powerFlashState != nil else { return }
        powerFlashState = nil
        apply(animated: true, spring: NotchCanvasView.Spring(response: Motion.Spring.calm.response, bounce: Motion.Spring.calm.bounce))
    }

    /// 最后一下之后 1.2 秒：内容先淡出，再沿 calm 收形状。
    private func retireLevel() {
        levelTimer = nil
        levelAnnounce?.cancel()
        levelAnnounce = nil
        meter = nil
        levelEdges.reset()
        levelYieldOpen = false
        apply(animated: true, spring: NotchCanvasView.Spring(response: Motion.Spring.calm.response,
                                                              bounce: Motion.Spring.calm.bounce))
    }

    private func scheduleLevelAnnouncement() {
        levelAnnounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let meter = self.meter else { return }
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                     userInfo: [.announcement: meter.ear.spoken,
                                                .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        levelAnnounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchLevelEars.announceDelay, execute: work)
    }

    // MARK: 全屏里出两耳

    /// 面板让开着（原生全屏桌面）时，两耳要不要出：先把面板露出来，看它在这张桌面上是不是真的看得见。
    func openLevelYield() {
        guard yieldsToSystem, !levelYieldOpen else { return }
        levelYieldOpen = true
        updateVisibility()
    }

    /// 露出来之后的可见性事实；查不到的项是 nil（按看不见处理）。
    func levelVisibilityFacts() -> NotchLevelSuppression.FullScreen {
        guard levelYieldOpen else { return .notVisible }
        return NotchLevelEars.fullScreenVisibility(panelVisible: isVisible, onActiveSpace: isOnActiveSpace,
                                                   occlusionVisible: occlusionState.contains(.visible))
    }

    func closeLevelYield() {
        guard levelYieldOpen else { return }
        levelYieldOpen = false
        updateVisibility()
    }

    var levelForProbe: (kind: String, value: Double)? {
        meter.map {
            switch $0.kind {
            case .volume: return (WSL10n.text("notch.level.volume", zh: "音量"), $0.value)
            case .brightness: return (WSL10n.text("notch.level.brightness", zh: "亮度"), $0.value)
            case .keyboardLight: return (WSL10n.text("notch.level.keyboardLight", zh: "键盘灯"), $0.value)
            }
        }
    }

    /// 探针：两耳此刻的宽、高、左耳符号、右耳条拉长了多少、条填了多少（没在出就是 nil）。
    var levelEarsForProbe: (width: CGFloat, height: CGFloat, symbol: String, stretch: Double, fill: Double)? {
        guard let meter, let island = shapeForProbe?.island else { return nil }
        let ear = meter.ear
        return (island.width, island.height, ear.symbol, ear.stretch?.points ?? 0, ear.value)
    }

    var compactForProbe: (leading: String?, trailing: String?, count: Int)? {
        displayCompact().map { ($0.leading, $0.trailing, $0.count) }
    }

    /// 第二颗岛：从这一颗旁边长出去。展开着的那一排不拆开。
    func split(showing text: String) {
        guard !isAuthenticating, !isExpanded, !text.isEmpty else { return }
        companionText = text
        isSplit = true
        updateVisibility()
        apply(animated: true)
    }

    func mergeSplit() {
        guard isSplit else { return }
        companionText = nil
        isSplit = false
        apply(animated: true)
    }

    var splitForProbe: (separated: Bool, retargeted: Bool, fades: Bool) { canvas.splitForProbe }

    /// 合成一排（M11）：窗口在左、正在进行的在右，竖线隔开，活动卡不再叠在上面。关着是旧样子。
    private(set) var mergedRow = false
    /// 这一排里正在进行的格的内容签名（NotchController 用它判断要不要原地换）。
    var ongoingSignatures: [String] { tiles.compactMap(\.ongoingSignature) }

    /// `merged`：窗口和正在进行的事合成一排。`tiles` 里窗口格在前、正在进行的格在后。
    func expand(with tiles: [NotchTile], merged: Bool = NotchController.mergedRowEnabled, animated: Bool = true) {
        guard !isAuthenticating else { return }
        guard acquireLease(.notchShelf) else { return }
        alertTimer?.invalidate()
        alertInfo = nil
        isExpanded = true
        mergedRow = merged
        lastShelfChangeAnimated = animated
        // 竖放的窄屏放不下六张：按这块屏的宽度少放几张，岛不出屏幕边。
        let home = NSScreen.screens.first { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }
        let room = (home?.frame.width ?? notch.width + 1000) - NotchRow.screenReserve
        let windows = tiles.filter { !$0.kind.isOngoing }
        let ongoing = tiles.filter { $0.kind.isOngoing }
        let fit = NotchRow.fit(windows: windows.count, ongoing: ongoing.count, room: room,
                               tail: ongoing.contains { $0.ongoing?.shelfCount != nil })
        self.tiles = Array(windows.prefix(fit.windows)) + Array(ongoing.prefix(fit.ongoing))
        if focus.isActive {
            // 键盘焦点在时，那一排被重新排过（缩略图之外的内容变了）：焦点还在就留着，没了重选。
            focus.setCells(focusCells())
            syncFilter()
            canvas.setTileFocus(focus.visibleFocusID, animated: false)
            reportFocusKind()
        }
        updateVisibility()
        apply(animated: animated)
    }

    /// 某一格的画面到了（后台截的）：只换这一格的图，不走 expand（那会清掉提醒、重算整个岛）。
    func updateTileSnapshot(id: CGWindowID, image: CGImage?) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].snapshot = image
        canvas.updateTileSnapshot(id: id, image: image)
    }

    /// 右段的格子里只是量变了（同一种画法）：原地改数字和环的终点，不走 expand，也不重排。
    func updateOngoingQuantities(_ next: [NotchTile]) {
        for tile in next {
            guard let index = tiles.firstIndex(where: { $0.id == tile.id }), let ongoing = tile.ongoing,
                  let current = tiles[index].ongoing, current.quantity != ongoing.quantity || current.quantityText != ongoing.quantityText else { continue }
            tiles[index].ongoing?.quantity = ongoing.quantity
            tiles[index].ongoing?.quantityText = ongoing.quantityText
            canvas.updateOngoingQuantity(id: tile.id, quantity: ongoing.quantity, text: ongoing.quantityText)
        }
    }

    func collapse() {
        guard !isAuthenticating else { return }
        endFocus()
        guard isExpanded else { return }
        // 那一排里摆过结束了的活动：算看过一次，之后不再留。
        let showedEnded = tiles.contains { $0.ongoing?.isEnded == true }
        isExpanded = false
        tiles = []
        apply(animated: true)
        releaseLease(.notchShelf)
        if showedEnded { onRowSeen?() }
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

    // MARK: - FS-03 文件拖近刘海

    private static let islandDragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")
    ]

    /// 系统里有东西被拖起来了。先只记下是哪一类并开始接拖放（文字、图片、链接也接），指针靠近了才垂下小岛。
    /// 平时刘海这一块只照今天的样子接文件（拖进来停 0.35 秒弹主屏幕），传感器没认出的拖动靠它兜底；
    /// 小岛不在时不画任何东西，也不吃菜单栏的点击。
    func beginFileDrop(kind: FileDragKind, env: FileDropEnvironment) {
        guard !isAuthenticating else { return }
        fileDrop = FileDropIslandModel(kind: kind, env: env, hit: .outside, notchWidth: notch.width)
        canvas.islandDragActive = true
        canvas.registerForDraggedTypes(Self.islandDragTypes)
    }

    /// 现在的事实变了（文件架满没满……）：原地换。
    func updateFileDropEnvironment(_ env: FileDropEnvironment) {
        guard var model = fileDrop, model.env != env else { return }
        model.env = env
        fileDrop = model
        if dropState != .none { apply(animated: false) }
    }

    /// 指针（Cocoa 坐标）移动了：靠近就垂下，进了岛就按所在的格点亮，出了岛 24 点就收。
    func updateFileDrop(pointer: CGPoint) {
        guard let model = fileDrop, !isAuthenticating, !yieldsToSystem else { return }
        let island = FileDropGeometry.island(notchMidX: notch.midX, screenTop: notch.maxY)
        let shown = dropState != .none
            ? FileDropGeometry.shouldKeep(pointer: pointer, island: island)
            : FileDropGeometry.shouldShow(pointer: pointer, screenTop: notch.maxY, notchMidX: notch.midX)
        let hit = shown ? FileDropGeometry.hit(pointer, island: island) : FileDropHit.outside
        setFileDropState(shown ? (hit == .outside ? .offered : .armed) : .none, hit: hit, model: model)
    }

    private func setFileDropState(_ state: DropState, hit: FileDropHit, model: FileDropIslandModel) {
        guard state != dropState || hit != model.hit else { return }
        // 指针换到另一格、而且那一格能用：触控板轻轻“咔”一下（有压感触控板时）。
        if case .cell(let cell) = hit, hit != model.hit, FileDropPlan.state(of: cell, kind: model.kind, env: model.env).enabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        var next = model
        next.hit = hit
        fileDrop = next
        dropState = state
        // 停在“用 App 打开”上够久，主屏幕弹开（今天的 0.35 秒）；离开那一格就取消。
        if hit == .cell(.openWith), FileDropPlan.state(of: .openWith, kind: model.kind, env: model.env).enabled {
            armFileDwell()
        } else {
            cancelFileDwell()
        }
        updateVisibility()
        apply(animated: true)
    }

    private func armFileDwell() {
        guard fileDwell == nil else { return }
        let timer = Timer(timeInterval: FileDropGeometry.openWithDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fileDwell = nil
                if self.fileDrop?.hit == .cell(.openWith) { self.onFileDropDwell?() }
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        fileDwell = timer
    }

    private func cancelFileDwell() {
        fileDwell?.invalidate()
        fileDwell = nil
    }

    /// 拖动结束（松手了、取消了、别处接走了）：收起小岛，刘海这一块不再接拖放。
    func endFileDrop() {
        cancelFileDwell()
        let wasShown = fileDrop != nil && dropState != .none
        let had = fileDrop != nil
        fileDrop = nil
        canvas.islandDragActive = false
        if had { canvas.registerForDraggedTypes([.fileURL]) }
        if wasShown {
            dropState = .none
            updateVisibility()
            apply(animated: true)
        }
    }

    /// 小岛上的拖放：进来、移动、离开、松手。
    private func islandDrag(_ info: NSDraggingInfo?, _ phase: IslandDragPhase) -> NSDragOperation {
        guard fileDrop != nil, !isAuthenticating else { return [] }
        switch phase {
        case .entered, .updated:
            guard let info else { return [] }
            updateFileDrop(pointer: convertPoint(toScreen: info.draggingLocation))
            return pendingRelease() == .nothing ? [] : Self.accepted(info)
        case .exited:
            cancelFileDwell()
            return []
        case .perform:
            guard let info else { return [] }
            updateFileDrop(pointer: convertPoint(toScreen: info.draggingLocation))
            let release = pendingRelease()
            cancelFileDwell()
            guard release != .nothing else { return [] }
            return onFileDrop?(release, info.draggingPasteboard) == true ? Self.accepted(info) : []
        }
    }

    /// 来源允许拷贝就给拷贝（访达里带 + 角标），否则给通用。
    private static func accepted(_ info: NSDraggingInfo) -> NSDragOperation {
        info.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }

    /// 现在松手会发生什么。
    private func pendingRelease() -> FileDropRelease {
        guard let model = fileDrop, dropState != .none else { return .nothing }
        return FileDropPlan.release(at: model.hit, kind: model.kind, env: model.env)
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

    /// 卷轴概览里拖着一扇窗靠近刘海（SS-04）：长成落点（用 catch 弹簧），离开用 calm 收回。
    /// 正在认证 / 放行占着、别的落点正在进行时不出（Core 里 approvalHolding 也会让松手不收）。
    func setStripLanding(_ on: Bool) {
        if on {
            guard !stripLanding, !isAuthenticating, dropState == .none, fileDrop == nil else { return }
            stripLanding = true
            dropState = .offered
            if !Motion.reduced { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            updateVisibility()
            apply(animated: true)
        } else {
            guard stripLanding else { return }
            stripLanding = false
            if dropState == .offered { dropState = .none }
            updateVisibility()
            apply(animated: true, spring: Self.calmSpring)
        }
    }

    private static var calmSpring: NotchCanvasView.Spring {
        let calm = Motion.reduced ? Motion.Spring.reducedNotch : Motion.Spring.calm
        return NotchCanvasView.Spring(response: calm.response, bounce: calm.bounce, initialVelocity: 0)
    }

    /// 指针进出：进来停一小会儿才展开（从菜单栏划过去不算），出去立刻收。
    private func hover(_ inside: Bool) {
        guard !isAuthenticating else { return }
        focusPointer(inside)
        hoverTimer?.invalidate()
        enterDeferred = false
        if inside, let still = pointerWhenGrown, NSEvent.mouseLocation == still {
            enterDeferred = true
            return
        }
        hoverGuarded = inside && NotchController.hoverGuardEnabled
        if hoverGuarded {
            let sample = canvas.pointerSample
            applyHover(hoverPolicy.enter(at: sample.point, time: sample.time, context: hoverContext))
            return
        }
        _ = hoverPolicy.exit()
        if inside {
            // 刘海上有东西时，岛马上往外长一点点；停够 0.12 秒再展开（从菜单栏划过去不算）。
            if compact != nil, !isExpanded, dropState == .none, alertInfo == nil, !hinting {
                hinting = true
                apply(animated: true)
            }
            hoverTimer = Timer.scheduledTimer(withTimeInterval: Motion.Hold.notchDwell, repeats: false) { [weak self] _ in
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

    /// LA-4 的环境：系统的 » 在就只认点击；这块屏在全屏桌面上（菜单栏滑下来时面板可能露着）不因悬停展开。
    private var hoverContext: NotchHoverPolicy.Context {
        NotchHoverPolicy.Context(clickOnly: menuBarOverflowShown, fullScreen: yieldsToSystem)
    }

    /// 指针在热区里动了（开关开着才算）。
    private func hoverMoved() {
        guard hoverGuarded, !isAuthenticating else { return }
        let sample = canvas.pointerSample
        applyHover(hoverPolicy.move(to: sample.point, time: sample.time, context: hoverContext))
    }

    /// 鼠标滚轮、惯性滚动：不算停留，也不重新计时（开关开着才算）。
    private func hoverScrolled() {
        guard hoverGuarded, !isAuthenticating else { return }
        applyHover(hoverPolicy.scroll(time: ProcessInfo.processInfo.systemUptime, context: hoverContext))
    }

    private func hoverDeadlineReached() {
        hoverTimer = nil
        guard hoverGuarded, !isAuthenticating else { return }
        applyHover(hoverPolicy.fire(time: ProcessInfo.processInfo.systemUptime, context: hoverContext))
    }

    /// 照 NotchHoverPolicy 的一步做：提示只往下长 3 点（calm）；到点展开；计时器只留一个，到点再问下一次。
    private func applyHover(_ step: NotchHoverPolicy.Step) {
        if step.expand {
            hoverTimer?.invalidate(); hoverTimer = nil
            hinting = false
            onHoverChanged?(true)
            return
        }
        let wantsHint = step.hint && compact != nil && !isExpanded && dropState == .none && alertInfo == nil
        if wantsHint != hinting {
            hinting = wantsHint
            let calm = Motion.reduced ? Motion.Spring.reducedNotch : Motion.Spring.calm
            apply(animated: true, spring: NotchCanvasView.Spring(response: calm.response, bounce: calm.bounce, initialVelocity: 0))
        }
        guard let deadline = step.deadline else {
            hoverTimer?.invalidate(); hoverTimer = nil
            return
        }
        // 已有一个在等：它到点时会拿到新的时刻再排，不为每次移动重排计时器。
        if hoverTimer?.isValid == true { return }
        let wait = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverDeadlineReached() }
        }
        timer.tolerance = NotchHoverPolicy.timerTolerance
        hoverTimer = timer
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
        /// 最小呈现的最小形（屏幕坐标）。开关关着或放不下时是空的。
        var minimum: [NotchMinimumShape] = []
    }

    /// 一排格子要占的岛宽（含两边 14 的边距和竖线）。一格没有时按一格算，和原来一样。
    private var rowLayout: NotchRow.Layout {
        let shown = shownTiles
        return NotchRow.layout(windows: shown.filter { !$0.kind.isOngoing }.count, ongoing: shown.filter { $0.kind.isOngoing }.count)
    }
    private var rowIslandWidth: Double {
        // 筛选之后一格也没有：写“没有匹配的”，那一排不窄于两格（LA-7）。
        if filterIDs != nil, shownTiles.isEmpty { return NotchRowFilter.emptyIslandWidth }
        return tiles.isEmpty ? NotchRow.pitch + 2 * NotchRow.edgeMargin - NotchRow.cellGap : rowLayout.islandWidth(minimum: 0)
    }

    /// 这一刻岛该是什么样：外框（Cocoa 坐标）、样式、面板要占的范围、两个肩。
    /// 展开时外框圆角 28、四周边距 14，格子圆角 14（HIG：同心、边距一致）。
    private func target() -> Target {
        var result = restingTarget()
        // 开关关着：就是原来的决定，一个字节不差。
        guard minimalPresentation else { return result }
        let shapes = minimumShapes(anchoredTo: result.hit)
        guard !shapes.isEmpty else { return result }
        result.minimum = shapes
        // 最小形在岛外：面板连它一起占，指针能点、画得出来。
        result.hit = shapes.reduce(result.hit) { $0.union($1.frame) }
        return result
    }

    /// 最小呈现（M13）：选中那件是紧凑，其余退成岛右侧的最小形。只在岛静止在紧凑样式（刘海两侧或无刘海胶囊）、
    /// 右边量到的空位放得下时才画；放不下、被更高的层占着、展开、提醒、认证、落点、音量亮度条时一颗都不画。
    private func minimumShapes(anchoredTo island: NSRect) -> [NotchMinimumShape] {
        guard !isAuthenticating, !isExpanded, dropState == .none, alertInfo == nil, meter == nil, pulled == 0 else { return [] }
        guard compactShape == (isVirtual ? CompactShape.pill : CompactShape.sides) else { return [] }
        let layout = NotchMinimalPresentation.layout(items: activityItems, selected: activitySelection, enabled: true)
        let placement: NotchMinimalPresentation.Placement = isVirtual ? .capsule : .notched
        let count = NotchMinimalPresentation.fittingCount(wanted: layout.minimum.count, room: room?.trailing, placement: placement)
        guard count > 0 else { return [] }
        let frames = NotchMinimalPresentation.frames(island: island, count: count, placement: placement)
        return zip(layout.minimum.prefix(count), frames).map { item, frame in
            NotchMinimumShape(id: item.id, label: NotchMinimalPresentation.label(for: item), tone: NotchInfoDot.tone(for: item),
                              fraction: NotchMinimalPresentation.arcFraction(for: item), frame: frame)
        }
    }

    private func restingTarget() -> Target {
        var (rect, style) = baseTarget()
        let resting = !isAuthenticating && !isExpanded && dropState == .none && alertInfo == nil
        // 音量亮度两耳比 34 宽：不画肩（S3），原来的肩跟着同一根弹簧收到 0；不跟下拉、悬停走；面板就占两耳那么宽。
        if meter != nil, resting {
            var ears = Target(rect: rect, style: style, hit: rect, compactSide: CGFloat(NotchLevelEars.earWidth))
            ears.shoulders = NotchLevelEars.drawsShoulders() && !isVirtual ? (1, 1) : (0, 0)
            return ears
        }
        if resting, pulled > 0 {
            let extra = Self.rubberBand(pulled, limit: (canPull?() ?? false) ? 84 : 18)
            rect.origin.y -= extra
            rect.size.height += extra
            if !isVirtual, rect.width < notch.width + 40 { rect = rect.insetBy(dx: -min(20, extra / 3), dy: 0) }
            style.cornerRadius = max(style.cornerRadius, NotchIsland.pullRadius(hardware, extra: extra))
            style.fill = .black
        } else if resting, hinting, compact != nil, hoverGuarded {
            // LA-4：提示只往下长 3 点，不往两边（两边是量过的）。
            rect = NotchHoverPolicy.hintRect(rect)
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

    /// 无刘海胶囊五态（R02）：开关开着，才把展开、提醒、紧凑重排到菜单栏下方 8 点，以胶囊中心为锚向下长；
    /// 交互态本来就在 notch.minY - 8，不动。开关关着或是真刘海屏，原样返回旧决定。
    private func baseTarget() -> (rect: NSRect, style: IslandStyle) {
        let legacy = legacyBaseTarget()
        guard isVirtual, capsuleBelowMenuBar, !isAuthenticating, dropState == .none, meter == nil else { return legacy }
        let state: NotchCapsule.State
        if isExpanded { state = .expanded }
        else if alertInfo != nil { state = .alert }
        else if compact != nil || displayCompact()?.leading != nil { state = .compact }
        else { return legacy }
        // 展开里有窗口格或活动卡时，内容按旧外框排版，不能压进 230×64：这时只换落点，不换尺寸。
        let hasContent = !tiles.isEmpty || !cardItems.isEmpty
        let size = NotchCapsule.size(state, compact: legacy.rect.size, alert: legacy.rect.size,
                                     interaction: legacy.rect.size)
        let shaped = state == .expanded && hasContent ? legacy.rect.size : size
        let rect = NotchCapsule.frame(size: shaped, slot: notch, belowMenuBar: true)
        var style = legacy.style
        style.cornerRadius = NotchCapsule.radius(height: rect.height)
        style.allCorners = true
        return (rect, style)
    }

    private func legacyBaseTarget() -> (rect: NSRect, style: IslandStyle) {
        if isAuthenticating {
            let screenWidth = screen?.frame.width ?? 1000
            // 640 是旧形状的保护；指挥态和选模型按稿用屏宽百分比（40% / 50%），只受屏宽减两侧安全边距限制。
            let widthCap: CGFloat = authenticationView is WS2ConductorView || authenticationView is WS2ModelPickerView ? .greatestFiniteMagnitude : 640
            let width = max(240, min(screenWidth - 44, max(notch.width, min(widthCap, interactionSize.width))))
            // Actual notch: content below the camera. Other displays: a detached, fully rounded capsule below the menu bar.
            let available = max(68, (screen?.visibleFrame.height ?? 600) - 80)
            let content = authenticationView as? any WS2LeaseContent
            let minimumHeight = content?.interactionMinimumHeight ?? 68
            let contentHeight = min(available, max(minimumHeight, min(480, interactionSize.height)))
            let height = isVirtual ? contentHeight : notch.height + contentHeight
            let top = isVirtual ? notch.minY - 8 : notch.maxY
            // 正在播放大卡：底角 28、不画肩（S3，和那一排同一种半岛）。
            let radius: CGFloat = isVirtual
                ? (authenticationView is NowPlayingCard ? NowPlayingCardLayout.bottomRadius : 34)
                : (content?.interactionCornerRadius ?? 24)
            return (NSRect(x: notch.midX - width / 2, y: top - height, width: width, height: height),
                    IslandStyle(cornerRadius: radius, allCorners: isVirtual, fill: .black, border: 0.5))
        }
        if stripLanding, dropState != .none {
            // 卷轴概览拖来的一扇：340 × 84，圆角 22，顶边贴着屏幕顶，横向居中在刘海上（稿 SS-04，数字在 StripNotchExchange）。
            return (StripNotchExchange.landingFrame(notch: notch),
                    IslandStyle(cornerRadius: StripNotchExchange.landingRadius, allCorners: false, fill: .black, border: 1))
        }
        if dropState != .none, fileDrop != nil {
            // 文件那一种：340 × 84，圆角 22，顶边贴着屏幕顶，上面一条绕着刘海排，下面一排三格（稿“拖近刘海”）。
            let rect = FileDropGeometry.island(notchMidX: notch.midX, screenTop: notch.maxY)
            return (rect, IslandStyle(cornerRadius: FileDropGeometry.islandCorner, allCorners: false, fill: .black, border: 1))
        }
        if dropState != .none {
            let zone = dropZone
            let rect = NSRect(x: zone.minX, y: zone.minY, width: zone.width, height: notch.maxY - zone.minY)
            // 硬件层永远纯黑：已对准只靠更粗的强调色边线，不填灰底（§6-2）。
            return (rect, IslandStyle(cornerRadius: 22, allCorners: false, fill: .black,
                                      border: dropState == .armed ? 2 : 1,
                                      borderColor: dropState == .armed ? NSColor.controlAccentColor.withAlphaComponent(0.9)
                                                                       : NotchPanel.hairline))
        }
        if isExpanded {
            // 半岛：从刘海顶边往下鼓（y = notch.maxY - height），内容绕传感器，不另加空白额头。
            let screenWidth = NSScreen.screens.first { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }?.frame.width ?? 1000
            // 合成一排（M11）：活动不再另起一张卡叠在窗口上面，右段的格子和窗口格同高、同一排。
            let stacksActivityCard = !mergedRow && !cardItems.isEmpty
            let width = min(screenWidth - CGFloat(NotchRow.screenReserve),
                            max(stacksActivityCard ? 420 : notch.width + 120, CGFloat(rowIslandWidth)))
            let rawBelow: CGFloat = stacksActivityCard ? (tiles.isEmpty ? 144 : 286) : (tiles.isEmpty ? 56 : 142)
            let below = NotchIsland.peninsulaContentHeight(rawBelow)
            let height = notch.height + below
            // 无刘海：S4 四角全圆、不画肩；真刘海仍从硬件肩长出。
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: 28, allCorners: isVirtual, fill: .black, border: 1))
        }
        if let alert = alertInfo, alert.peek != nil {
            // 换歌一瞥：宽不变（还是两耳那么宽），只往下鼓 30（63.5），底角 24；不走半岛的矮档，那一档会把它撑到 72。
            let side = NotchRoomPolicy.activitySide(earWidth: sideWidth, leading: room?.leading, trailing: room?.trailing)
            let width = notch.width + side * 2
            let height = CGFloat(NowPlayingPeek.height(notchHeight: Double(notch.height)))
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: CGFloat(NowPlayingPeek.cornerRadius), allCorners: isVirtual, fill: .black, border: 1,
                                borderColor: NotchPanel.hairline))
        }
        if let alert = alertInfo {
            let teaching = alert.demo != nil
            let width = Self.alertWidth(notch: notch, teaching: teaching)
            // 短暂提醒也可短下鼓；高度走半岛矮档，避开临界带。
            let height = notch.height + NotchIsland.peninsulaContentHeight(teaching ? 84 : 52)
            let border: NSColor
            switch alert.tone {
            case .problem: border = NSColor.systemOrange.withAlphaComponent(0.75)
            case .tip: border = NSColor.controlAccentColor.withAlphaComponent(0.8)
            default: border = NotchPanel.hairline
            }
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: 24, allCorners: isVirtual, fill: .black,
                                border: alert.tone == .problem || alert.tone == .tip ? 1.5 : 1, borderColor: border))
        }
        if let ears = displayCompact(), ears.leading != nil {
            // 音量 / 亮度 / 键盘灯：两耳各 76、总宽 = 刘海宽 + 152、高同刘海，不往下鼓（《音量与亮度》稿）。
            // 真刘海底角取刘海自己的底角（island.hug）、顶角直角；无刘海屏是同高的胶囊（S4，不画假刘海）。
            if meter != nil { return levelEarsTarget() }
            switch compactShape {
            case .sides:
                // LA-2：画多宽就要量到多宽。以前按 max(sideWidth, 54) 画、只验 ≥ 26，26–54 点的图标会被盖住。
                // 电量那一下：宽 = 刘海 + 68（每耳 34）、高同刘海。
                return (notch.insetBy(dx: -(ears.flash != nil ? sideWidth
                                            : NotchRoomPolicy.activitySide(earWidth: sideWidth, leading: room?.leading,
                                                                           trailing: room?.trailing)), dy: 0),
                        IslandStyle(cornerRadius: NotchIsland.compactRadius(hardware), allCorners: false, fill: .black, border: 0))
            case .chin:
                if isVirtual {
                    let rect = NSRect(x: notch.midX - 36, y: notch.minY - 12, width: 72, height: 12)
                    return (rect, IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: rect.height, preferred: capsuleCorner),
                                              allCorners: true, fill: .black, border: 0))
                }
                return (NSRect(x: notch.minX, y: notch.minY - 8, width: notch.width, height: notch.height + 8),
                        IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
            case .pill, .pending:
                let width: CGFloat = 200
                let height = max(22, isVirtual ? notch.height - 6 : notch.height)
                let y = isVirtual ? notch.minY + 3 : notch.maxY - height
                return (NSRect(x: notch.midX - width / 2, y: y, width: width, height: height),
                        IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: height, preferred: capsuleCorner),
                                    allCorners: true, fill: .black, border: 0))
            }
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
                return (rect, IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: rect.height, preferred: capsuleCorner),
                                          allCorners: true, fill: .black, border: 0))
            case .chin:
                // 刘海旁边被菜单或菜单栏图标占着：退回刘海下面的下巴，一个点一扇窗。
                if isVirtual {
                    let rect = NSRect(x: notch.midX - 36, y: notch.minY - 12, width: 72, height: 12)
                    return (rect, IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: rect.height, preferred: capsuleCorner),
                                              allCorners: true, fill: .black, border: 0))
                }
                return (NSRect(x: notch.minX, y: notch.minY - 8, width: notch.width, height: notch.height + 8),
                        IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
            case .pending:
                break
            }
        }
        // 和刘海一样大（变形的第一帧、停稳藏回去的那一下）：底角等于刘海自己的底角（`island.hug`）。
        // 无刘海静止态：槽位本身也是胶囊（S4）。
        if isVirtual {
            return (notch, IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: notch.height, preferred: capsuleCorner),
                                       allCorners: true, fill: .black, border: 0))
        }
        return (notch, IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
    }

    /// 音量亮度两耳的外框与样式：宽 = 刘海 + 2 × 76，高 = 刘海，顶边贴着刘海顶。
    private func levelEarsTarget() -> (rect: NSRect, style: IslandStyle) {
        let width = CGFloat(NotchLevelEars.totalWidth(notchWidth: Double(notch.width)))
        let rect = NSRect(x: notch.midX - width / 2, y: notch.minY, width: width, height: notch.height)
        if isVirtual {
            return (rect, IslandStyle(cornerRadius: NotchIsland.capsuleRadius(height: rect.height, preferred: capsuleCorner),
                                      allCorners: true, fill: .black, border: 0))
        }
        return (rect, IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
    }

    /// 这一下的形状（弹簧按形状取令牌，见 `Motion.notchSpring`）。优先级与 `target()` 一致。
    private func motionShape() -> Motion.NotchShape {
        // 文件架卡和一排是同一个动作的两头（点末格长成卡），用同一根“展开”弹簧。
        if isAuthenticating { return (authenticationView is NowPlayingCard || authenticationView is FileShelfView) ? .expanded : .interaction }
        if dropState != .none { return .drop }
        if alertInfo != nil { return .alert }
        if meter != nil { return .meter }
        if isExpanded { return .expanded }
        guard displayCompact() != nil else { return .minimum }
        switch compactShape {
        case .sides: return .compact
        case .chin: return .chin
        case .pill, .pending: return .capsuleCompact
        }
    }

    /// 这一下该用的弹簧：按形状取令牌；没有动量的（指针停上来、收回）不回弹，提醒带一点弹性，
    /// 要手指介入的用 `pop`；减少动态效果时岛直接到位（`morph` 不挂弹簧），这里只剩内容淡化的时长。
    private func spring() -> NotchCanvasView.Spring {
        let token = Motion.notchSpring(for: motionShape())
        return NotchCanvasView.Spring(response: token.response, bounce: token.bounce)
    }

    /// roomOnly：只是量到的空位变了（内容、状态都没变）：肩因此长出、收掉时淡入淡出，不跟着弹簧长（S5）。
    private func apply(animated: Bool, spring custom: NotchCanvasView.Spring? = nil, roomOnly: Bool = false) {
        // 岛按真实外框画（刘海高 33.5 点这种半点也照画），只有面板落在整点上（窗口只能落在整点上），岛在面板里按半点偏移放：
        // 顶边贴着屏幕边缘，不留一像素的缝；也不比刘海多出半点。
        let target = target()
        let rect = target.rect, style = target.style
        // 两耳只亮一小会儿：点击穿透，菜单栏照常能点（稿“形状”一节）。
        ignoresMouseEvents = meter != nil
        // 平时（什么都没有）岛就是刘海本身：不画，免得圆角和刘海的圆角对不齐、从边上露出黑点。
        let bare = !isVirtual && rect == notch && pulled == 0
        let resting = !isExpanded && dropState == .none && alertInfo == nil
        let shape = compactShape
        let visual = displayCompact()
        // 半岛展开时保留紧凑左右耳（谁 / 数）在传感器两侧，格子绕着排——相对位置继承，不留额头。
        let shelfEars = isExpanded && (cardItems.isEmpty || mergedRow) && compact != nil
            && dropState == .none && alertInfo == nil && meter == nil
        let compactShown = (resting && visual != nil && (shape != .chin || visual?.leading != nil)) || shelfEars
        let chinShown = resting && visual?.leading == nil && meter == nil && compact != nil && shape == .chin
        let extra = resting && pulled > 0 ? Self.rubberBand(pulled, limit: (canPull?() ?? false) ? 84 : 18) : 0
        // 音量亮度两耳不管紧凑退成了什么：左右各 76，一定是两侧的版式。
        let earShape: CompactShape = shelfEars || meter != nil ? .sides : shape
        var content = NotchCanvasView.Content(
            tiles: isExpanded ? tiles : [],
            dots: chinShown ? (compact?.count ?? 0) : 0,
            dotsChanged: chinShown && (compact?.changed ?? false),
            dotsY: isVirtual ? 4 : 2.5 + extra,
            compact: compactShown ? (shelfEars ? compact : visual) : nil,
            compactSlots: compactShown
                ? compactSlots(in: rect.size, shape: earShape, side: target.compactSide, anchorToNotch: shelfEars)
                : nil,
            alert: (!isExpanded && dropState == .none) ? alertInfo : nil,
            hint: hintText(), notchHeight: notch.height,
            pullIcon: extra > 0 ? compact?.icon : nil, pullExtra: extra, pullProgress: min(1, extra / 50),
            drop: dropState, dropChoice: dropChoice,
            dropDisabled: dropState == .none || fileDrop != nil ? [] : Set(DropChoice.allCases.filter { isDisabled($0) }.map(\.rawValue)),
            fileDrop: dropState == .none ? nil : fileDrop,
            activities: (dropState == .none && alertInfo == nil && meter == nil && !(isExpanded && mergedRow)) ? cardItems : [],
            activitySelection: activitySelection,
            activitiesExpanded: isExpanded && !cardItems.isEmpty && !mergedRow,
            secondaryDot: showsSecondaryDot,
            companion: companionText)
        content.shownIDs = isExpanded ? filterIDs : nil
        content.query = isExpanded && focus.isActive ? focus.query : ""
        content.notchWidth = notch.width
        content.stripLanding = stripLanding && dropState != .none
        // 封面耳：只在真刘海的两侧版式里换成封面；边长按这一耳的主体宽、肩宽、刘海高算，放不下就是 nil（退回今天的样子）。
        if var ears = content.compact, ears.music != nil, !shelfEars, let slots = content.compactSlots {
            let shoulder = target.shoulders.leading > 0 ? Double(hardware?.shoulderExtent ?? 0) : 0
            ears.music?.coverSide = earShape == .sides && !isVirtual
                ? NowPlayingEars.coverSide(body: Double(slots.leading.width), shoulder: shoulder, notchHeight: Double(notch.height))
                : nil
            content.compact = ears
        }
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
        content.minimum = target.minimum.map {
            var shape = $0
            shape.frame = shape.frame.offsetBy(dx: -container.minX, dy: -container.minY)
            return shape
        }
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
        // 封面耳露没露（NP-6）：变了才告诉 NotchController，由它决定建、拆录音。
        let earShown = content.compact?.music?.coverSide != nil && content.compact?.level == nil && !shelfEars
        if earShown != showsMusicEar {
            showsMusicEar = earShown
            onMusicEarChange?()
        }
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
        canvas.pulse()
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

    /// 紧凑两耳。有实时活动时左耳是那一件、右耳是进度；窗口个数退成一个点。
    /// 音量和亮度也走这两耳，不另开一扇窗。
    private func displayCompact() -> Compact? {
        if let meter {
            // 左耳一个会变的符号，右耳一根白条；不写百分比（读屏念数，见 scheduleLevelAnnouncement）。
            let ear = meter.ear
            return Compact(count: 0, changed: false, leading: ear.spoken, level: ear)
        }
        if let flash = powerFlashState, !isExpanded, dropState == .none, alertInfo == nil, !isAuthenticating {
            return Compact(count: 0, changed: false, leading: flash.spoken, trailing: flash.trailing, flash: flash)
        }
        if let item = activityItems.first(where: { $0.id == activitySelection }) ?? activityItems.first,
           !isExpanded, dropState == .none, alertInfo == nil {
            let timer = item.kind == .timer
            let calendarEar = item.kind == .calendar
            let focus = item.kind == .focus || timer || calendarEar
            let tone: Compact.ProgressTone = timer ? (item.isPaused ? .timerPaused : .timer)
                : (calendarEar ? (item.calendar?.joinable == true ? .calendarJoin : .calendar)
                   : (focus ? (NotchEarText.isRest(item) ? .rest : .focus) : .playback))
            // 推送流开着（它才有封面）时，音乐的两耳换成封面 + 静止取色点；关着一律是今天的样子。
            let music = NowPlayingEars.usesCoverEars(streamEnabled: NowPlayingStream.isEnabled, isMusic: item.kind == .music)
                ? MusicEar(paused: item.isPaused, artwork: musicArtwork,
                                   spoken: NowPlayingEars.spoken(title: item.title, artist: item.subtitle, paused: item.isPaused),
                                   coverSide: nil)
                : nil
            // 文件架个数（优先级最低，只在没有别的持续活动时轮到）：左耳托盘符号，右耳个数，不写字。
            if item.kind == .shelf, let count = Int(item.trailing ?? "") {
                return Compact(count: compact?.count ?? 0, changed: false, leading: "", leadingSymbol: item.symbol,
                               trailing: item.trailing, dotTone: .accent, shelfSpoken: NotchShelfEars.spoken(count: count))
            }
            // 番茄钟：左耳一圈环加“专注”或“休息”，不画符号，也不画横条。计时器：左耳只有橙环，没有字。
            return Compact(pid: compact?.pid, icon: compact?.icon, count: compact?.count ?? 0, changed: false,
                           leading: item.title,
                           leadingSymbol: focus ? nil : (item.symbol.isEmpty ? "circle.fill" : item.symbol),
                           trailing: Self.earTrailing(item),
                           progress: item.isStale ? nil : (focus ? (item.progress.fractionValue ?? 0) : nil),
                           quantity: focus || item.isStale ? .unknown : item.progress,
                           progressTone: tone, progressStyle: focus ? .ring : .bar, dotTone: NotchInfoDot.tone(for: item),
                           // 过期的不转圈、不猜：右耳只剩“—”。
                           sessionPhase: item.isStale ? nil : item.sessionPhase, music: music, calendar: item.calendar,
                           stale: item.isStale)
        }
        return compact
    }

    /// 右耳的字：来源给了就用来源的；百分比只给本身是百分比的种类（`NotchEarText`）。
    static func earTrailing(_ item: NotchActivity) -> String { NotchEarText.trailing(item) }

    /// 紧凑样式左右两段在岛里的位置。side：每侧主体多宽（画肩时从 sideWidth 里扣掉了肩）。
    /// anchorToNotch：展开时两耳贴着硬件刘海左右，不漂到整块岛的外沿。
    private func compactSlots(in size: NSSize, shape: CompactShape, side: CGFloat,
                              anchorToNotch: Bool = false) -> (leading: NSRect, trailing: NSRect) {
        if anchorToNotch {
            let ear = max(side, Self.narrowestSide)
            let notchX = (size.width - notch.width) / 2
            let y = size.height - notch.height
            return (NSRect(x: max(0, notchX - ear), y: y, width: ear, height: notch.height),
                    NSRect(x: min(size.width - ear, notchX + notch.width), y: y, width: ear, height: notch.height))
        }
        if shape == .pill || shape == .pending || shape == .chin {
            return (NSRect(x: 4, y: 0, width: size.width / 2 - 4, height: size.height),
                    NSRect(x: size.width / 2, y: 0, width: size.width / 2 - 4, height: size.height))
        }
        return (NSRect(x: 0, y: 0, width: side, height: size.height),
                NSRect(x: size.width - side, y: 0, width: side, height: size.height))
    }

    private func hintText() -> String? {
        if stripLanding, dropState != .none { return StripNotchExchange.landingLine }
        if dropState != .none, fileDrop != nil { return nil }
        switch dropState {
        case .armed: return isDisabled(dropChoice)
                ? NotchSmallBehaviour.disabledReason
                : WSL10n.text("notch.drop.release", zh: "松手：%@", dropChoice.title)
        case .offered: return WSL10n.text("notch.drop.offer", zh: "拖到这里，排好或收进刘海")
        case .confirmed: return dropChoice == .tuck ? WSL10n.text("notch.drop.confirmed", zh: "正在收起") : dropChoice.title
        case .none:
            if pulled > 0, compact == nil { return WSL10n.text("silent.launcher.open", zh: "启动台") }
            return isExpanded && tiles.isEmpty && (cardItems.isEmpty || mergedRow)
                ? WSL10n.text("notch.launchpad.hint", zh: "点一下回主屏幕 · 左右滑换 App") : nil
        }
    }
}

/// 最小呈现里的一颗最小形：哪件活动、读屏标签、语气色、进度弧（没有比例就是 nil，只画圆点）、外框。
struct NotchMinimumShape: Equatable {
    var id: String
    var label: String
    var tone: NotchInfoDot.Tone
    var fraction: Double?
    var frame: NSRect
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
        /// 落点上放不下而灰掉的格子（DropChoice.rawValue）。
        var dropDisabled: Set<Int> = []
        /// FS-03：文件那一种落点小岛（三格加两耳）。nil 就是窗口那一种（五格）或没有。
        var fileDrop: FileDropIslandModel? = nil
        /// SS-04：卷轴概览拖来一扇窗的落点（340 × 84，只有托盘符号和“松手收进刘海”，没有五个去处）。
        var stripLanding = false
        var activities: [NotchActivity] = []
        var activitySelection: String? = nil
        var activitiesExpanded: Bool = false
        /// 被更高的层挡住的提醒：只留一个点，不把那一句再说一遍。
        var secondaryDot: Bool = false
        /// 旁边那颗岛上的一句。空着就是合并。
        var companion: String? = nil
        /// 在那一排里打字筛选（LA-7）：留着的格子（nil 是全部）、筛选字、刘海宽（字写在刘海左边那一段）。
        /// 都不进 `same`：筛选只是原地并拢，不整排淡出淡入。
        var shownIDs: Set<CGWindowID>? = nil
        var query = ""
        var notchWidth: CGFloat = 0
        /// 最小呈现的最小形（画布坐标）。它们在岛外，自己一层，不参与“是不是同一份内容”。
        var minimum: [NotchMinimumShape] = []

        /// 是不是同一份内容（只是岛的大小、位置变了）：同一份就原地挪，不淡出淡入。
        /// 故意不比较格子的画面：画面是后台截到后原地换的（updateTileSnapshot），换图不该让整排淡出淡入。
        /// 紧凑两耳的曲名/进度用 layoutSame：数字与文案 content replace，不整岛重建。
        func same(as other: Content) -> Bool {
            tiles.map(\.id) == other.tiles.map(\.id) && tiles.map(\.changed) == other.tiles.map(\.changed)
                && tiles.map(\.place) == other.tiles.map(\.place) && tiles.map(\.kind) == other.tiles.map(\.kind)
                && activities.isEmpty == other.activities.isEmpty && activitiesExpanded == other.activitiesExpanded
                && dots == other.dots && dotsChanged == other.dotsChanged
                && (compact?.layoutSame(as: other.compact) ?? (other.compact == nil))
                && alert?.id == other.alert?.id && ((alert?.peek != nil && other.alert?.peek != nil) || alert?.title == other.alert?.title)
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
    /// 鼠标滚轮或惯性滚动经过刘海（LA-4：不算停留）。触控板手指还在板上的滚动是手势，不报。
    var onScrollNoise: (() -> Void)?
    /// 最近一次进来或移动时指针在哪（屏幕坐标）、什么时候（事件时钟 = 开机以来的秒数）。
    private(set) var pointerSample: (point: NSPoint, time: TimeInterval) = (.zero, 0)
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    var onTileAccessory: ((CGWindowID) -> Void)?
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
    /// 边线的渐变遮罩：顶边看不见，往下 3 点起渐显，到 20 点全显；只在岛的上角是肩的那种样子（不是四角全圆）时挂上。
    private let keyMask = CAGradientLayer()
    /// 内容的遮罩：和岛同一个形状、同一套弹簧。
    private let clipHost = NSView()
    private let clip = CALayer()
    private var current: NotchContentView?
    /// 右耳 5 根的样子（NP-6）：新换上的内容层接着用。
    private var musicWave = NowPlayingWave.dots
    func setMusicWave(_ wave: NowPlayingWave) {
        musicWave = wave
        current?.setMusicWave(wave)
    }
    /// 卡住提示里新的那排键帽按一下（CoachEcho）。
    func echoAlertKeys() { current?.echoAlertKeys() }
    /// 键盘焦点亮在哪一格；内容换了（整排重建）时新的一层按它亮起。
    private(set) var focusedTileID: CGWindowID?
    func setTileFocus(_ id: CGWindowID?, bump: FocusNavigator.Direction? = nil, animated: Bool = true) {
        focusedTileID = id
        current?.setFocus(id, bump: bump, animated: animated)
    }
    @discardableResult
    func activateTile(_ id: CGWindowID) -> Bool { current?.activateTile(id) ?? false }
    /// 提醒里的图标在屏幕上的位置（点提醒时窗口从这里起飞）。
    var alertIconScreenRect: NSRect? { current?.alertIconScreenRect }
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
    private var presentGeneration = 0
    private var contentWatch: Timer?
    private var contentLink: CADisplayLink?
    private lazy var contentLinkProxy = ContentWatchLinkProxy(owner: self)
    private var contentWatchGeneration: Int?
    private var contentWatchStart: CGSize?
    private var contentWatchTarget: CGSize?
    private var contentWatchBegan: CFTimeInterval = 0
    private var contentWatchFade: TimeInterval = 0
    private var contentWatchLag: TimeInterval = 0
    private let companion = CALayer()
    private let companionLabel = CATextLayer()
    private var companionRetargeted = false

    /// 某一格的画面到了：记进当前内容（下次比较、重排时用得上），再交给那一格的视图原地换上。
    func updateTileSnapshot(id: CGWindowID, image: CGImage?) {
        if let index = shown?.tiles.firstIndex(where: { $0.id == id }) { shown?.tiles[index].snapshot = image }
        current?.updateSnapshot(id: id, image: image)
    }

    /// 某一格的量变了：记进当前内容，再交给那一格原地改数字和环的终点。
    func updateOngoingQuantity(id: CGWindowID, quantity: NotchActivity.Quantity, text: String?) {
        if let index = shown?.tiles.firstIndex(where: { $0.id == id }) {
            shown?.tiles[index].ongoing?.quantity = quantity
            shown?.tiles[index].ongoing?.quantityText = text
        }
        current?.updateOngoingQuantity(id: id, quantity: quantity, text: text)
    }
    private var pull: (distance: CGFloat, samples: [(TimeInterval, CGFloat)])?
    /// 两个肩所在的那层窗口（NotchPanel 给，不知道硬件形状时是 nil）：岛变形时肩跟着岛的上角走。
    var shoulders: NotchShoulders?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // 硬件刘海一直是黑底，原生子控件也统一按深色画；其它产品窗口仍跟随系统。
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.masksToBounds = false
        island.backgroundColor = NSColor.black.cgColor
        island.cornerCurve = .continuous
        island.masksToBounds = true
        island.frame = bounds
        layer?.addSublayer(island)
        companion.backgroundColor = NSColor.black.cgColor
        companion.cornerCurve = .continuous
        companion.opacity = 0
        companion.isHidden = true
        companionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        companionLabel.fontSize = 12
        companionLabel.alignmentMode = .center
        companionLabel.foregroundColor = NSColor.white.cgColor
        companionLabel.contentsScale = 2
        companion.addSublayer(companionLabel)
        layer?.insertSublayer(companion, below: island)
        keyLine.cornerCurve = .continuous
        keyLine.borderWidth = 0
        keyMask.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        keyMask.startPoint = CGPoint(x: 0.5, y: 1)
        keyMask.endPoint = CGPoint(x: 0.5, y: 0)
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
        companion.position = CGPoint(x: companion.position.x + delta.dx, y: companion.position.y + delta.dy)
        CATransaction.commit()
        for view in clipHost.subviews { view.setFrameOrigin(NSPoint(x: view.frame.minX + delta.dx, y: view.frame.minY + delta.dy)) }
        for view in minimumViews { view.setFrameOrigin(NSPoint(x: view.frame.minX + delta.dx, y: view.frame.minY + delta.dy)) }
    }

    /// 退场淡出还没做完又来了新目标：打断淡出，立刻从当前外框接上。
    private var contentExitGeneration = 0
    private var contentExitPending = false
    /// 退场淡出完成后要接上的变形。放在 self 上，避免把 Content / done 送进 @Sendable 回调。
    /// 不存那一刻的外框：内容淡出的 0.14 秒里旧形状还在飞，performMorph 真正开始时自己重读呈现层。
    private var pendingExitMorph: (
        rect: NSRect, style: NotchPanel.IslandStyle, content: Content, spring: Spring?,
        scale: (leading: CGFloat, trailing: CGFloat),
        snap: (leading: Bool, trailing: Bool), shoulderFade: Bool, done: () -> Void
    )?

    /// 变到 rect（画布坐标）。spring 为 nil 时立刻到位（跟手的时候）。
    /// shoulders：两个肩各长出多少（0…1），和岛在同一个 transaction 里挂同参数的叠加弹簧；
    /// shoulderSnap：这一侧的肩本来就看不出来（和硬件重合、岛没画），直接收掉不动画；shoulderFade：只是空位变了，肩淡入淡出。
    /// 退场：丰富内容先淡出，形状再收回（稿 / 文法）。半路又改方向则打断淡出。
    func morph(to rect: NSRect, style: NotchPanel.IslandStyle, content: Content, spring: Spring?,
               shoulders scale: (leading: CGFloat, trailing: CGFloat) = (0, 0),
               shoulderSnap snap: (leading: Bool, trailing: Bool) = (false, false), shoulderFade: Bool = false,
               done: @escaping () -> Void) {
        contentExitGeneration += 1
        let exitGeneration = contentExitGeneration
        if contentExitPending {
            contentExitPending = false
            pendingExitMorph = nil
            if let outgoing = current {
                outgoing.alphaValue = 0
                outgoing.removeFromSuperview()
                current = nil
                shown = nil
            }
            performMorph(to: rect, style: style, content: content, spring: spring,
                         shoulders: scale, shoulderSnap: snap,
                         shoulderFade: shoulderFade, done: done)
            return
        }
        // 减少动态效果：不先淡出再等形状，岛直接到位，内容在 performMorph 里交叉淡化。
        if spring != nil, !Motion.reduced, Self.shouldExitContentFirst(from: shown, to: content), let outgoing = current, !outgoing.isEmpty {
            stopContentWatch()
            presentGeneration += 1
            outgoing.inert = true
            contentExitPending = true
            pendingExitMorph = (rect, style, content, spring, scale, snap, shoulderFade, done)
            // 退场：内容 0.10 秒淡出，停 0.04 秒，再收形状（`Motion.Fade`）。
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Motion.Fade.out
                outgoing.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.contentExitGeneration == exitGeneration else { return }
                    outgoing.removeFromSuperview()
                    if self.current === outgoing {
                        self.current = nil
                        self.shown = nil
                    }
                    // 停一小拍：这一拍里又来了新目标（morph 把 contentExitGeneration 往前推了），就不接旧的。
                    DispatchQueue.main.asyncAfter(deadline: .now() + Motion.Fade.gap) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.contentExitGeneration == exitGeneration, self.contentExitPending else { return }
                            self.contentExitPending = false
                            guard let pending = self.pendingExitMorph else { return }
                            self.pendingExitMorph = nil
                            self.performMorph(to: pending.rect, style: pending.style, content: pending.content,
                                              spring: pending.spring,
                                              shoulders: pending.scale, shoulderSnap: pending.snap,
                                              shoulderFade: pending.shoulderFade, done: pending.done)
                        }
                    }
                }
            })
            return
        }
        performMorph(to: rect, style: style, content: content, spring: spring,
                     shoulders: scale, shoulderSnap: snap,
                     shoulderFade: shoulderFade, done: done)
    }

    /// 展开 / 提醒 / 落点退回紧凑或空手：字先淡，形状再收。
    static func shouldExitContentFirst(from shown: Content?, to next: Content) -> Bool {
        guard let shown else { return false }
        let wasRich = shown.alert != nil || !shown.tiles.isEmpty || shown.activitiesExpanded || shown.drop != .none
        let nowRich = next.alert != nil || !next.tiles.isEmpty || next.activitiesExpanded || next.drop != .none
        return wasRich && !nowRich
    }

    /// 把还在飞的旧 morph 按轴接力到新目标。岛、遮罩、边线、渐变遮罩同一时刻挂的是同参数、
    /// 同一刻开始的动画（位移成正比），所以速度从 island 那份算，各层 from 各自读。
    /// 每根轴：旧动画在飞 → 它此刻的有符号物理速度 ÷ 该轴自己的剩余行程（新目标 − 呈现值）；
    /// 不在飞 → 保留调用者传进来的初速度（甩动手感），不覆盖。
    /// 剩余行程近零但速度还在 → 有限 kick 关键帧；宽、高、圆角的 kick 不许把量推成负（floor）。
    private func handoffAxes(to target: (rect: NSRect, radius: CGFloat),
                             presented: NSRect, presentedRadius: CGFloat,
                             spring: Spring, now: CFTimeInterval) -> MorphShape {
        let layerNow = island.convertTime(now, from: nil)
        func axis(_ keyPath: String, delta: Double, floor: Double?, fallback: Double) -> MorphAxis? {
            let live: Double?
            if let old = island.animation(forKey: "morph.\(keyPath)") as? CASpringAnimation,
               old.isAdditive, old.beginTime > 0, old.duration > 0,
               let from = (old.fromValue as? NSNumber)?.doubleValue {
                live = MorphRetarget.liveVelocity(of: MorphRetarget.OldAxis(mass: old.mass, stiffness: old.stiffness,
                                                                           damping: old.damping, from: from,
                                                                           normalizedVelocity: old.initialVelocity,
                                                                           beginTime: old.beginTime,
                                                                           duration: old.duration),
                                                  at: layerNow)
            } else if let frames = island.animation(forKey: "morph.\(keyPath)") as? CAKeyframeAnimation {
                // 上一次接力用了 kick 关键帧：段内斜率就是此刻的瞬时速度（曲线是解析解的采样）。
                live = Self.keyframeVelocity(frames, at: layerNow)
            } else {
                live = nil
            }
            guard let plan = MorphRetarget.handoff(remainingTravel: delta, liveVelocity: live,
                                                   fallbackVelocity: fallback, response: spring.response,
                                                   dampingRatio: 1 - Double(spring.bounce), floor: floor) else { return nil }
            return MorphAxis(velocity: plan.initialVelocity, kick: plan.kick)
        }
        let callerVelocity = Double(spring.initialVelocity)
        return MorphShape(
            positionX: (from: Double(presented.midX - target.rect.midX),
                        axis: axis("position.x", delta: Double(target.rect.midX - presented.midX),
                                   floor: nil, fallback: callerVelocity)),
            positionY: (from: Double(presented.midY - target.rect.midY),
                        axis: axis("position.y", delta: Double(target.rect.midY - presented.midY),
                                   floor: nil, fallback: callerVelocity)),
            width: (from: Double(presented.width - target.rect.width),
                    axis: axis("bounds.size.width", delta: Double(target.rect.width - presented.width),
                               floor: -Double(target.rect.width), fallback: callerVelocity)),
            height: (from: Double(presented.height - target.rect.height),
                     axis: axis("bounds.size.height", delta: Double(target.rect.height - presented.height),
                                floor: -Double(target.rect.height), fallback: callerVelocity)),
            radius: (from: Double(presentedRadius - target.radius),
                     axis: axis("cornerRadius", delta: Double(target.radius - presentedRadius),
                                floor: -Double(target.radius), fallback: callerVelocity)))
    }

    /// kick 关键帧动画此刻的瞬时速度：段内线性插值的斜率（曲线本身是 120 Hz 的解析解采样）。
    static func keyframeVelocity(_ frames: CAKeyframeAnimation, at time: CFTimeInterval) -> Double? {
        guard frames.isAdditive, frames.beginTime > 0, frames.duration > 0,
              let keyTimes = frames.keyTimes, let rawValues = frames.values,
              rawValues.count == keyTimes.count, rawValues.count >= 2 else { return nil }
        let elapsed = (time - frames.beginTime) / frames.duration
        guard elapsed >= 0, elapsed < 1 else { return nil }
        let values = rawValues.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard values.count == rawValues.count else { return nil }
        var index = 0
        while index + 2 < keyTimes.count, keyTimes[index + 1].doubleValue < elapsed { index += 1 }
        let t0 = keyTimes[index].doubleValue, t1 = keyTimes[index + 1].doubleValue
        let dt = (t1 - t0) * frames.duration
        guard dt > 1e-9 else { return nil }
        return (values[index + 1] - values[index]) / dt
    }

    /// kick 关键帧的位移减半（渐变遮罩的位置 = 尺寸一半，速度也跟着减半）；弹簧路径的
    /// 归一化速度不用减：它按各自行程折算，同一条弹簧上行程减半速度也减半，比值不变。
    private func halve(_ axis: MorphAxis?) -> MorphAxis? {
        guard let axis else { return nil }
        guard let kick = axis.kick else { return axis }
        return MorphAxis(velocity: axis.velocity, kick: (kick.values.map { $0 / 2 }, kick.times))
    }

    private func performMorph(to rect: NSRect, style: NotchPanel.IslandStyle, content: Content, spring: Spring?,
                              shoulders scale: (leading: CGFloat, trailing: CGFloat),
                              shoulderSnap snap: (leading: Bool, trailing: Bool),
                              shoulderFade: Bool,
                              done: @escaping () -> Void) {
        // 富有内容退场时形状收得晚（0.10 淡出 + 0.04 一拍）：真正开始时重读呈现层，
        // 不复用 morph() 那一刻的旧位置——期间岛可能已经动过。
        let presented = island.presentation()?.frame ?? island.frame
        let presentedRadius = CGFloat(island.presentation()?.cornerRadius ?? island.cornerRadius)
        let presentedKey = keyLine.presentation()?.frame ?? keyLine.frame
        let presentedClip = clip.presentation()?.frame ?? clip.frame
        let now = CACurrentMediaTime()
        // 减少动态效果：岛的外框和圆角直接跳到终点，不挂弹簧，也不做 position / bounds 动画；只交叉淡化内容。
        // 呈现层还没进过渲染（width 为 0）时同样不挂动画：没有可接的起点，直接换模型值。
        let motion = Motion.reduced ? nil : (presented.width > 0 ? spring : nil)
        let shape = motion.map { handoffAxes(to: (rect, style.cornerRadius), presented: presented,
                                             presentedRadius: presentedRadius, spring: $0, now: now) }
        stripMorph(island)
        stripMorph(clip)
        stripMorph(keyLine)
        stripMorph(keyMask)
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
        // 渐变描边：只画两侧和底边，顶边不画；四角全圆的胶囊整圈照旧。
        if style.allCorners || style.border <= 0 {
            keyLine.mask = nil
        } else {
            keyMask.frame = CGRect(origin: .zero, size: keyFrame.size)
            keyMask.locations = NotchSmallBehaviour.keyLineLocations(layerHeight: keyFrame.height, overscan: 2)
                .map { NSNumber(value: $0) }
            keyLine.mask = keyMask
        }
        if let motion, var shape, presented.width > 0 {
            add(motion, key: "morph", to: island, shape: shape, now: now)
            // 遮罩和岛同一坐标系、同一刻挂同参数动画：from 换成自己的呈现值，轴计划原样复用。
            shape.positionX = (Double(presentedClip.midX - rect.midX), shape.positionX.axis)
            shape.positionY = (Double(presentedClip.midY - rect.midY), shape.positionY.axis)
            shape.width = (Double(presentedClip.width - rect.width), shape.width.axis)
            shape.height = (Double(presentedClip.height - rect.height), shape.height.axis)
            add(motion, key: "morph", to: clip, shape: shape, now: now)
            // 边线在岛坐标系里：位置 = 尺寸增量的一半（中心 = 尺寸一半），位置轴接宽、高的速度
            // （归一化速度按各自行程折算，行程减半速度也减半，比值不变；kick 的位移要减半）。
            shape.positionX = (Double(presentedKey.midX - keyFrame.midX), halve(shape.width.axis))
            shape.positionY = (Double(presentedKey.midY - keyFrame.midY), halve(shape.height.axis))
            shape.width = (Double(presentedKey.width - keyFrame.width), shape.width.axis)
            shape.height = (Double(presentedKey.height - keyFrame.height), shape.height.axis)
            add(motion, key: "morph", to: keyLine, shape: shape, now: now)
            if keyLine.mask != nil {
                // 渐变遮罩跟边线同坐标系：frame 是 (0,0,keyFrame 尺寸)，中心 = 尺寸一半，
                // 位置增量 = 尺寸增量的一半；速度轴同宽、高（kick 位移减半，归一化速度比值不变）。
                shape.positionX = (Double(presentedKey.width - keyFrame.width) / 2, halve(shape.width.axis))
                shape.positionY = (Double(presentedKey.height - keyFrame.height) / 2, halve(shape.height.axis))
                shape.radius = (0, nil)
                add(motion, key: "morph", to: keyMask, shape: shape, now: now)
            }
        }
        // 肩的尖角 = 岛的两个上角（换成屏幕坐标：肩在另一层窗口里）。肩自己记着上一次的位置和大小，
        // 挂的是同参数、同一刻开始的叠加弹簧，所以横向位移正好是 moved.dx ∓ resized.width / 2，半路打断也跟得住。
        // 肩仍是自己的动画路径（fluid-retarget-plan：后续批次再同步它的逐轴速度），本批不动它的物理。
        if let shoulders, let origin = window?.frame.origin {
            shoulders.place(leading: NSPoint(x: origin.x + rect.minX, y: origin.y + rect.maxY),
                            trailing: NSPoint(x: origin.x + rect.maxX, y: origin.y + rect.maxY),
                            scale: scale, snap: snap, spring: Motion.reduced ? nil : spring, fade: shoulderFade)
        }
        CATransaction.commit()
        present(content, in: rect, from: presented, animated: spring != nil)
        placeCompanion(content.companion, beside: rect, spring: spring)
        placeMinimum(content.minimum, island: rect)
    }

    // MARK: 最小形（M13）

    /// 在岛外右侧的最小形。关着时一颗也没有，下面的每一处都是空转。
    private var minimumViews: [NotchMinimumView] = []
    /// 指针是从最小形上进来的：这时不当作“停在刘海上”去展开，等它移到岛上再算。
    private var hoverHeldByMinimum = false
    private var pressedMinimum: NotchMinimumView?

    private func minimumView(at event: NSEvent) -> NotchMinimumView? {
        guard !minimumViews.isEmpty else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return minimumViews.first { $0.frame.contains(point) }
    }

    /// 最小形的出现、挪位、退场。弹簧用 `calm`（0.34 / 1.0）；减少动态效果时不挪位置，只淡。
    private func placeMinimum(_ shapes: [NotchMinimumShape], island: NSRect) {
        guard !shapes.isEmpty || !minimumViews.isEmpty else { return }
        let reduced = Motion.reduced
        let motion = Spring(response: Motion.Spring.calm.response, bounce: Motion.Spring.calm.bounce)
        let wanted = Set(shapes.map(\.id))
        for view in minimumViews where !wanted.contains(view.shapeID) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Motion.fadeDuration
                view.animator().alphaValue = 0
            }, completionHandler: { [weak view] in
                MainActor.assumeIsolated { view?.removeFromSuperview() }
            })
        }
        minimumViews.removeAll { !wanted.contains($0.shapeID) }
        for shape in shapes {
            if let view = minimumViews.first(where: { $0.shapeID == shape.id }) {
                let before = view.layer?.presentation()?.frame ?? view.frame
                view.update(shape)
                guard view.frame != shape.frame else { continue }
                view.frame = shape.frame
                if !reduced, let layer = view.layer {
                    add(motion, key: "minimum", to: layer, shape: MorphShape(
                        positionX: (Double(before.midX - shape.frame.midX), MorphAxis(velocity: 0, kick: nil)),
                        positionY: (Double(before.midY - shape.frame.midY), MorphAxis(velocity: 0, kick: nil)),
                        width: (0, nil), height: (0, nil), radius: (0, nil)), now: CACurrentMediaTime())
                }
            } else {
                let view = NotchMinimumView(shape: shape)
                view.onSelect = { [weak self] id in self?.onActivitySelect?(id) }
                view.frame = shape.frame
                view.alphaValue = 0
                addSubview(view)
                minimumViews.append(view)
                // 从岛的右边缘长出来：位置从紧贴岛边的地方接到终点，同时淡入。
                if !reduced, let layer = view.layer {
                    add(motion, key: "minimum", to: layer, shape: MorphShape(
                        positionX: (Double(island.maxX - shape.frame.width / 2 - shape.frame.midX),
                                    MorphAxis(velocity: 0, kick: nil)),
                        positionY: (0, nil), width: (0, nil), height: (0, nil), radius: (0, nil)),
                        now: CACurrentMediaTime())
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.fadeDuration
                    view.animator().alphaValue = 1
                }
            }
        }
    }

    private func stripMorph(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] where key.hasPrefix("morph") {
            layer.removeAnimation(forKey: key)
        }
    }

    /// 一根标量轴怎么接：nil = 不动；kick 非空时交给关键帧（剩余行程近零只剩惯性）；
    /// velocity 是换算好的归一化初速度（旧动画在飞）或调用者给的初速度（不在飞，保留甩动手感）。
    private struct MorphAxis {
        var velocity: Double
        var kick: (values: [Double], times: [Double])?
    }
    /// 变形的五根标量轴：中点 x/y、宽、高、圆角。逐轴独立挂加法弹簧，各自带自己的归一化初速度。
    /// 中点、宽高、圆角各接各的：二维 keyPath 只能带一个初速度，宽和高的速度会互相顶掉。
    private struct MorphShape {
        var positionX: (from: Double, axis: MorphAxis?)
        var positionY: (from: Double, axis: MorphAxis?)
        var width: (from: Double, axis: MorphAxis?)
        var height: (from: Double, axis: MorphAxis?)
        var radius: (from: Double, axis: MorphAxis?)
    }

    private func add(_ spring: Spring, key: String, to layer: CALayer, shape: MorphShape, now: CFTimeInterval) {
        // CASpring 设明确的 beginTime（同一层时钟）：接力核对可以按同一瞬间算速度，不靠提交时刻。
        let begin = layer.convertTime(now, from: nil)
        func axis(_ keyPath: String, from: Double, zero: Double, axis: MorphAxis?) {
            guard let axis else { return }
            // 归一化速度的换算依据（25 批实测）：物理初速 = initialVelocity × (to − from)；
            // 加法动画 to 是 0，from 是该轴的位移。
            if let kick = axis.kick {
                let frames = CAKeyframeAnimation(keyPath: keyPath)
                frames.isAdditive = true
                frames.calculationMode = .linear
                frames.values = kick.values.map { NSNumber(value: $0) }
                frames.keyTimes = kick.times.map { NSNumber(value: min(1, $0 / (kick.times.last ?? 1))) }
                frames.duration = kick.times.last ?? 0
                frames.beginTime = begin
                layer.add(frames, forKey: "\(key).\(keyPath)")
                return
            }
            guard from != 0 else { return }
            let animation = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce)
            animation.keyPath = keyPath
            animation.isAdditive = true
            animation.fromValue = from
            animation.toValue = zero
            animation.initialVelocity = CGFloat(axis.velocity)
            animation.duration = animation.settlingDuration
            animation.beginTime = begin
            layer.add(animation, forKey: "\(key).\(keyPath)")
        }
        axis("position.x", from: shape.positionX.from, zero: 0, axis: shape.positionX.axis)
        axis("position.y", from: shape.positionY.from, zero: 0, axis: shape.positionY.axis)
        axis("bounds.size.width", from: shape.width.from, zero: 0, axis: shape.width.axis)
        axis("bounds.size.height", from: shape.height.from, zero: 0, axis: shape.height.axis)
        axis("cornerRadius", from: shape.radius.from, zero: 0, axis: shape.radius.axis)
    }

    /// 这一段行程的宽度走到四成，内容才淡入。减少动态效果不等形状。
    static func contentHasReachedFourTenths(from: CGFloat, to: CGFloat, now: CGFloat) -> Bool {
        let span = abs(to - from)
        guard span > 0.5 else { return true }
        return abs(now - from) / span >= Motion.Fade.shapeGate
    }

    /// 宽、高两者里走得更远的那个到了四成就算（下巴这种只变高的转场也能等形状）。
    static func contentHasReachedFourTenths(from: CGSize, to: CGSize, now: CGSize) -> Bool {
        let wide = abs(to.width - from.width) > 0.5, tall = abs(to.height - from.height) > 0.5
        guard wide || tall else { return true }
        var progress: CGFloat = 0
        if wide { progress = max(progress, abs(now.width - from.width) / abs(to.width - from.width)) }
        if tall { progress = max(progress, abs(now.height - from.height) / abs(to.height - from.height)) }
        return progress >= Motion.Fade.shapeGate
    }

    private func stopContentWatch() {
        contentWatch?.invalidate()
        contentWatch = nil
        contentLink?.invalidate()
        contentLink = nil
    }

    /// 形状走到四成的时刻由面板所在屏的显示器时钟盯着，120 Hz 屏不晚一帧；到了或换了内容就停，空闲时没有任何定时。
    fileprivate func contentWatchStep() {
        guard let generation = contentWatchGeneration, presentGeneration == generation,
              let start = contentWatchStart, let target = contentWatchTarget else { stopContentWatch(); return }
        let now = (island.presentation() ?? island).frame.size
        let expired = CACurrentMediaTime() - contentWatchBegan > 1.0
        guard expired || Self.contentHasReachedFourTenths(from: start, to: target, now: now) else { return }
        stopContentWatch()
        guard let view = current else { return }
        let fade = contentWatchFade, lag = contentWatchLag
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            view.animator().alphaValue = 1
        }
        view.revealSecondLayer(after: lag, duration: fade)
    }

    /// 内容：同一份就原地挪到新位置；换了就旧的一层先淡出，新的一层等形状走到四成再淡入（都被岛裁着）。
    private func present(_ content: Content, in rect: NSRect, from start: NSRect, animated: Bool) {
        stopContentWatch()
        if let current, let shown, shown.same(as: content) {
            current.place(in: rect, content: content)
            self.shown = content
            return
        }
        presentGeneration += 1
        let generation = presentGeneration
        let reduced = Motion.reduced
        if let outgoing = current {
            outgoing.inert = true
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.Fade.fadeOut(reduced: reduced)
                    outgoing.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { outgoing.removeFromSuperview() }
                })
            } else {
                outgoing.removeFromSuperview()
            }
        }
        let incoming = NotchContentView(content: content)
        incoming.setMusicWave(musicWave)
        incoming.isHidden = authenticationView != nil
        incoming.onTileClicked = { [weak self] id, rect in self?.onTileClicked?(id, rect) }
        incoming.activityView.onSelect = { [weak self] id in self?.onActivitySelect?(id) }
        incoming.activityView.onAction = { [weak self] action in self?.onActivityAction?(action) }
        incoming.onTileHover = { [weak self] id, inside, rect in self?.onTileHover?(id, inside, rect) }
        incoming.onTileAccessory = { [weak self] id in self?.onTileAccessory?(id) }
        clipHost.addSubview(incoming)
        if let authenticationView { clipHost.addSubview(authenticationView, positioned: .above, relativeTo: incoming) }
        incoming.place(in: rect, content: content)
        if focusedTileID != nil { incoming.setFocus(focusedTileID, animated: false) }
        // 一排刚展开：格子按序号错开淡入（合成一排和旧布局都一样；整排替换、减少动态效果时不错开）。
        if animated, !reduced, shown?.tiles.isEmpty ?? true { incoming.staggerTiles(fade: Motion.Fade.fadeIn(reduced: false)) }
        if animated, !incoming.isEmpty {
            incoming.alphaValue = 0
            let fadeDuration = Motion.Fade.fadeIn(reduced: reduced)
            let lag = Motion.Fade.secondLayerLag(reduced: reduced)
            if reduced || Self.contentHasReachedFourTenths(from: start.size, to: rect.size, now: start.size) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fadeDuration
                    incoming.animator().alphaValue = 1
                }
                incoming.revealSecondLayer(after: lag, duration: fadeDuration)
            } else {
                contentWatchGeneration = generation
                contentWatchStart = start.size
                contentWatchTarget = rect.size
                contentWatchBegan = CACurrentMediaTime()
                contentWatchFade = fadeDuration
                contentWatchLag = lag
                if let screen = window?.screen ?? NSScreen.main {
                    let link = screen.displayLink(target: contentLinkProxy, selector: #selector(ContentWatchLinkProxy.step(_:)))
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                    link.add(to: .main, forMode: .common)
                    contentLink = link
                } else {
                    // 拿不到显示器时钟：定时器只当节拍，判断仍按呈现层的位置。
                    let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.contentWatchStep() }
                    }
                    timer.tolerance = 0.002
                    RunLoop.main.add(timer, forMode: .common)
                    contentWatch = timer
                }
            }
        }
        current = incoming
        shown = content
    }

    private func companionSize(for text: String?) -> (width: CGFloat, height: CGFloat) {
        let height: CGFloat = 28
        let string = text ?? (companionLabel.string as? String) ?? ""
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = (string as NSString).size(withAttributes: [.font: font]).width
        return (max(36, ceil(textWidth) + 24), height)
    }

    /// 第二颗岛。半路改方向时从当前外框接上。减少动态效果位置不动，只淡。
    private func placeCompanion(_ text: String?, beside islandRect: NSRect, spring: Spring?) {
        let reduced = Motion.reduced
        let size = companionSize(for: text)
        let height = size.height
        let width = size.width
        let apart = CGRect(x: islandRect.maxX + 8, y: islandRect.maxY - height, width: width, height: height)
        let together = CGRect(x: islandRect.midX - width / 2, y: islandRect.midY - height / 2, width: width, height: height)
        let destination = text == nil ? together : apart
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let presented = companion.presentation()?.frame ?? companion.frame
        let wasVisible = (companion.presentation()?.opacity ?? companion.opacity) > 0.01 && !companion.isHidden
        let inflight = companion.animation(forKey: "companion.position") != nil
            || companion.animation(forKey: "companion.bounds.size") != nil
        if inflight { companionRetargeted = true }
        companion.isHidden = false
        companion.cornerRadius = height / 2
        if let text { companionLabel.string = text }
        companionLabel.frame = CGRect(x: 12, y: (height - 16) / 2, width: width - 24, height: 16)
        let fromOpacity = companion.presentation()?.opacity ?? companion.opacity
        let toOpacity: Float = text == nil ? 0 : 1
        if reduced {
            companion.removeAnimation(forKey: "companion.position")
            companion.removeAnimation(forKey: "companion.bounds.size")
            companion.frame = wasVisible ? presented : together
        } else {
            companion.frame = destination
            if text != nil || wasVisible {
                let from = wasVisible ? presented : together
                let motion = spring ?? Spring(response: Motion.Spring.expand.response, bounce: Motion.Spring.expand.bounce)
                // 第二颗岛仍是自己的路径：各轴沿用调用者给的同一个归一化初速度（旧行为不变）。
                let axis = MorphAxis(velocity: Double(motion.initialVelocity), kick: nil)
                add(motion, key: "companion", to: companion, shape: MorphShape(
                    positionX: (Double(from.midX - destination.midX), axis),
                    positionY: (Double(from.midY - destination.midY), axis),
                    width: (Double(from.width - destination.width), axis),
                    height: (Double(from.height - destination.height), axis),
                    radius: (0, nil)), now: CACurrentMediaTime())
            }
        }
        if text != nil || wasVisible || reduced {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = toOpacity
            // companion 只淡：出现/消失都走令牌时长（减少动态效果用 `reducedNotch`）。
            fade.duration = reduced ? Motion.Spring.reducedNotch.response : Motion.Spring.calm.response
            companion.opacity = toOpacity
            companion.add(fade, forKey: "companion.opacity")
        } else {
            companion.opacity = 0
        }
        CATransaction.commit()
    }

    var splitForProbe: (separated: Bool, retargeted: Bool, fades: Bool) {
        let showing = companion.opacity > 0.01
        let apart = companion.frame.minX + 1 >= island.frame.maxX
        let moving = companion.animation(forKey: "companion.position") != nil
            || companion.animation(forKey: "companion.bounds.size") != nil
        let fading = companion.animation(forKey: "companion.opacity") != nil
        return (Motion.reduced ? showing : apart && showing, companionRetargeted, !moving && (fading || Motion.reduced))
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

    /// 收进来一扇窗的那一下：宽和高各一根 calm，在终点上被踢一脚初速度，再自己回到终点。顶边不动。
    /// 峰值约 +14 pt / +6 pt，约 0.05 秒到峰，是弹簧解出来的，不是关键帧写死的。
    func pulse() {
        guard !Motion.reduced else { return }
        let kick = SwellKick.samples()
        guard let last = kick.last, last.time > 0 else { return }
        let keyTimes = kick.map { NSNumber(value: $0.time / last.time) }
        func bump(_ layer: CALayer) {
            let size = CAKeyframeAnimation(keyPath: "bounds.size")
            size.isAdditive = true
            size.calculationMode = .linear
            size.values = kick.map { NSValue(size: NSSize(width: $0.width, height: $0.height)) }
            size.keyTimes = keyTimes
            size.duration = last.time
            let position = CAKeyframeAnimation(keyPath: "position")
            position.isAdditive = true
            position.calculationMode = .linear
            position.values = kick.map { NSValue(point: NSPoint(x: 0, y: -$0.height / 2)) }
            position.keyTimes = keyTimes
            position.duration = last.time
            layer.add(size, forKey: "pulse.size")
            layer.add(position, forKey: "pulse.position")
        }
        bump(island)
        bump(clip)
        // 两条竖边各往外挪这一帧鼓出的宽度的一半，和岛同一条时间。
        shoulders?.pulse(widthSamples: kick.map(\.width), keyTimes: keyTimes, duration: last.time)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerSample = (mouseScreenPoint(event), event.timestamp)
        if minimumView(at: event) != nil { hoverHeldByMinimum = true; return }
        hoverHeldByMinimum = false
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        hoverHeldByMinimum = false
        holdTimer?.invalidate(); holdTimer = nil; if mouseDragAxis == nil { pressedAt = nil }; onHover?(false)
    }
    override func mouseMoved(with event: NSEvent) {
        pointerSample = (mouseScreenPoint(event), event.timestamp)
        if hoverHeldByMinimum, minimumView(at: event) == nil { hoverHeldByMinimum = false; onHover?(true); return }
        onPointerMoved?()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 点刘海（不在某一格上）：按下时岛就鼓一下（点几下鼓多大），松开才算；按下后拖开了不算。
    var onPress: ((Int) -> Void)?
    /// 点在正在播放的紧凑左耳或右耳上（一下）：交给面板的 openNowPlayingCard()，默认行为 = 照原来的 onPress(1)。
    var onNowPlayingEar: (() -> Void)?
    private var pressedAt: NSPoint?
    private var mouseDragAxis: Bool?
    private var mouseDragSamples: [(TimeInterval, CGPoint)] = []
    private func mouseScreenPoint(_ event: NSEvent) -> NSPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
    override func mouseDown(with event: NSEvent) {
        guard authenticationView == nil else { return }
        // 按在最小形上：只记下是哪一颗，松手还在它上面才算点一下（互换）；不鼓岛、不起长按计时。
        pressedMinimum = minimumView(at: event)
        if pressedMinimum != nil { holdTimer?.invalidate(); pressedAt = nil; return }
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
        pulse()
    }
    override func mouseUp(with event: NSEvent) {
        if let pressed = pressedMinimum {
            pressedMinimum = nil
            if minimumView(at: event) === pressed { pressed.select() }
            return
        }
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
        if event.clickCount == 1, current?.isOnMusicEar(windowPoint: event.locationInWindow) == true, let onNowPlayingEar {
            onNowPlayingEar()
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
            // 收起时不切换活动，但仍吞掉手势，不落到今日/资料库导航。
            guard shown.activitiesExpanded else { return }
            let index = shown.activities.firstIndex { $0.id == shown.activitySelection } ?? 0
            let next = max(0, min(shown.activities.count - 1, index + (event.deltaX > 0 ? -1 : 1)))
            onActivitySelect?(shown.activities[next].id)
        } else { onNavigation?(event.deltaX > 0 ? .today : .library) }
    }

    /// 拖着文件停在刘海上 0.35 秒：主屏幕弹开给它挑 App（Finder 的弹簧文件夹）；没等弹开就松手也一样。
    var onFiles: (([URL]) -> Void)?
    private var fileDwell: Timer?
    /// FS-03：文件架开着，系统拖动期间由落点小岛接拖放（三格）；关着就是上面今天的做法。
    var islandDragActive = false
    var onIslandDrag: ((NSDraggingInfo?, IslandDragPhase) -> NSDragOperation)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if islandDragActive, let route = onIslandDrag { return route(sender, .entered) }
        legacyOperation = legacyEntered(sender)
        return legacyOperation
    }
    private var legacyOperation: NSDragOperation = []
    private func legacyEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard authenticationView == nil else { return [] }
        let files = LaunchpadView.fileURLs(sender)
        guard !files.isEmpty else { return [] }
        fileDwell?.invalidate()
        pulse()
        fileDwell = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fileDwell = nil
                self?.onFiles?(files)
            }
        }
        return .generic
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if islandDragActive, let route = onIslandDrag { return route(sender, .updated) }
        return legacyOperation
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if islandDragActive, let route = onIslandDrag { _ = route(sender, .exited); return }
        fileDwell?.invalidate()
        fileDwell = nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if islandDragActive, let route = onIslandDrag { return !route(sender, .perform).isEmpty }
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
        if !event.hasPreciseScrollingDeltas || event.momentumPhase != [] { onScrollNoise?() }
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
        let presented = layer.presentation()?.position ?? layer.position
        for key in layer.animationKeys() ?? [] where key.hasPrefix("shoulder") {
            layer.removeAnimation(forKey: key)
        }
        layer.position = point
        layer.transform = CATransform3DMakeScale(new, new, 1)
        guard !first else { return }
        if snap {
            for name in layer.animationKeys() ?? [] where name.hasSuffix(".transform.scale") { layer.removeAnimation(forKey: name) }
        }
        let key = "shoulder"
        guard let spring else {
            // 跟手的时候（岛没有弹簧、立刻到位）：位置跟着到；肩长出、收掉仍走一段不回弹的弹簧，不在一帧里跳没。
            // 减少动态效果：肩和岛一起直接到位，不留一段缩放动画。
            if old != new, !snap, !Motion.reduced {
                animate(layer, "transform.scale", from: old - new, zero: 0,
                        spring: NotchCanvasView.Spring(response: Motion.Spring.calm.response,
                                                       bounce: Motion.Spring.calm.bounce), key: key)
            }
            return
        }
        if presented != point {
            animate(layer, "position", from: NSValue(point: NSPoint(x: presented.x - point.x, y: presented.y - point.y)),
                    zero: NSValue(point: .zero), spring: spring, key: key)
        }
        if snap { return }
        if fade, old == 0, new > 0 {
            // 只是空位变了才长出来的：在终点淡入，不从 0 长（时长走 `calm` / `reducedNotch`）。
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.duration = Motion.fadeDuration
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

    /// 岛鼓一下时，两条竖边各往外挪这一帧宽度的一半。samples 是弹簧解，点与点之间线性插值。
    func pulse(widthSamples: [Double], keyTimes: [NSNumber], duration: CFTimeInterval) {
        for (layer, sign) in [(leading, -1.0), (trailing, 1.0)] {
            let move = CAKeyframeAnimation(keyPath: "position.x")
            move.isAdditive = true
            move.calculationMode = .linear
            move.values = widthSamples.map { NSNumber(value: sign * $0 / 2) }
            move.keyTimes = keyTimes
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
    var onTileAccessory: ((CGWindowID) -> Void)?
    let activityView = NotchActivityView(frame: .zero)
    private let hint = NSTextField(labelWithString: "")
    private let dots = NotchDotsView()
    private let compactView = NotchCompactView()
    private let mark = NotchSecondaryMark()
    private let alertView = NotchAlertView()
    /// 左段窗口和右段正在进行的之间那一条竖线（只在两段都有格子时露出）。
    private let divider = NotchRowDivider()
    func echoAlertKeys() { alertView.echoKeys() }
    func setMusicWave(_ wave: NowPlayingWave) { compactView.setMusicWave(wave) }
    private let pullView = NSImageView()
    /// 落点里的符号：托盘，收下后换成对勾（原地换，符号自己的过渡）。
    private let glyph = NSImageView()
    private var glyphState: NotchPanel.DropState = .none
    /// FS-03：文件那一种落点小岛（三格加两耳）。
    private let fileIsland = FileDropIslandView()
    /// 落点小岛上的五个去处。
    private var choiceViews: [NSImageView] = []
    private var tileViews: [NotchTileView] = []
    private(set) var pullIconRect: NSRect?
    let isEmpty: Bool
    /// 打字筛选（LA-7）：刘海左边那一段的字（13 半粗）加一个光标，以及一格也没有时的话。
    private let queryLabel = NSTextField(labelWithString: "")
    private let queryCursor = NSView()
    private let noMatchLabel = NSTextField(labelWithString: NotchRowFilter.noMatchText)
    /// 上一次排版时留着的格子：变了才动画。
    private var placedShownIDs: Set<CGWindowID>?
    private var placedOnce = false

    init(content: NotchCanvasView.Content) {
        isEmpty = content.tiles.isEmpty && content.hint == nil && content.compact == nil && content.alert == nil
            && content.activities.isEmpty && content.dots == 0 && !content.dotsChanged && content.pullIcon == nil
            && !content.secondaryDot && content.fileDrop == nil
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
        addSubview(mark)
        addSubview(alertView)
        addSubview(activityView)
        divider.isHidden = true
        addSubview(divider)
        queryLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        queryLabel.textColor = .white
        queryLabel.alignment = .right
        queryLabel.lineBreakMode = .byClipping
        queryLabel.isHidden = true
        queryCursor.wantsLayer = true
        queryCursor.layer?.backgroundColor = NSColor.white.cgColor
        queryCursor.layer?.cornerRadius = 0.75
        queryCursor.isHidden = true
        noMatchLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noMatchLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        noMatchLabel.alignment = .center
        noMatchLabel.isHidden = true
        addSubview(queryLabel)
        addSubview(queryCursor)
        addSubview(noMatchLabel)
        pullView.imageScaling = .scaleProportionallyUpOrDown
        pullView.image = content.pullIcon
        addSubview(pullView)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.contentTintColor = .white
        addSubview(glyph)
        fileIsland.isHidden = true
        addSubview(fileIsland)
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
            view.setPosition((content.tiles.firstIndex { $0.id == tile.id } ?? 0) + 1, of: content.tiles.count)
            view.onClick = { [weak self] rect in self?.onTileClicked?(tile.id, rect) }
            view.onAccessory = { [weak self] in self?.onTileAccessory?(tile.id) }
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

    func updateOngoingQuantity(id: CGWindowID, quantity: NotchActivity.Quantity, text: String?) {
        tileViews.first { $0.tileID == id }?.setQuantity(quantity, text: text)
    }

    /// 键盘焦点亮在哪一格（nil 全熄）。`bump`：那一格到头了，顶一下。
    func setFocus(_ id: CGWindowID?, bump: FocusNavigator.Direction? = nil, animated: Bool = true) {
        for view in tileViews {
            let lit = view.tileID == id
            view.setFocused(lit, bump: lit ? bump : nil, animated: animated)
        }
    }

    var alertIconScreenRect: NSRect? { alertView.iconScreenRect }

    /// 格子先全透明，再按序号一格一格淡入：第 i 格在形状开始后 0.09 + 0.04 × i 秒起。
    func staggerTiles(fade: TimeInterval) {
        guard tileViews.count > 0 else { return }
        for view in tileViews where !view.isHidden { view.alphaValue = 0 }
        for (index, view) in tileViews.enumerated() where !view.isHidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchSmallBehaviour.tileFadeDelay(index: index)) { [weak view] in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = fade
                        view.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// 键盘上的 Return 打开某一格。找不到这一格返回 false。
    @discardableResult
    func activateTile(_ id: CGWindowID) -> Bool {
        guard let view = tileViews.first(where: { $0.tileID == id }) else { return false }
        view.activateFromKeyboard()
        return true
    }

    /// 第二层（副句、按钮）比第一层晚 `lag` 秒淡入。第一层刚开始淡入时调用；`lag` 为 0（减少动态效果）时不分层。
    func revealSecondLayer(after lag: TimeInterval, duration: TimeInterval) {
        guard lag > 0, !activityView.isHidden else { return }
        activityView.setSecondLayer(alpha: 0, duration: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + lag) { [weak self] in
            MainActor.assumeIsolated { self?.activityView.setSecondLayer(alpha: 1, duration: duration) }
        }
    }

    /// 辅助功能的 hit-test 可以从后台线程进来：AppKit 随时可能调，方法不能挂 MainActor 隔离
    /// （真机 --notch 探针实证：隔离断言在进方法体之前炸出 SIGTRAP）。主线程内才碰状态。
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { inert ? nil : super.hitTest(point) }
    }

    /// 窗口坐标里的这一点，是不是落在正在播放的紧凑左耳或右耳上（NP-2：点耳朵的入口）。
    func isOnMusicEar(windowPoint: NSPoint) -> Bool {
        !inert && compactView.containsMusicEar(convert(windowPoint, from: nil))
    }

    /// 按岛的终点排好（rect：画布坐标里岛的外框）。
    func place(in rect: NSRect, content: NotchCanvasView.Content) {
        frame = rect
        let bounds = NSRect(origin: .zero, size: rect.size)
        dots.frame = bounds
        dots.update(count: content.dots, changed: content.dotsChanged, y: content.dotsY)
        compactView.isHidden = content.compact == nil
        compactView.frame = bounds
        compactView.update(content.compact, slots: content.compactSlots)
        mark.frame = bounds
        mark.visible = content.secondaryDot
        alertView.isHidden = content.alert == nil
        alertView.frame = NSRect(x: 0, y: 0, width: rect.width, height: max(0, rect.height - content.notchHeight))
        alertView.update(content.alert)
        activityView.isHidden = content.activities.isEmpty || !content.activitiesExpanded
        let activityHeight: CGFloat = content.activitiesExpanded ? 142 : 30
        activityView.frame = NSRect(x: 0, y: max(0, rect.height - content.notchHeight - activityHeight), width: rect.width, height: activityHeight)
        activityView.update(content.activities, selected: content.activitySelection, expanded: content.activitiesExpanded)
        // 外框圆角 28、四周边距 14；格子之间 8。窗口在左，竖线，正在进行的在右（M11）。
        // 打字筛选时（LA-7）只排留着的格子；离开的淡出，剩下的并拢（第一次排版直接到位，不动画）。
        let top = rect.height - content.notchHeight
        let shownIDs = content.shownIDs
        func isShown(_ index: Int) -> Bool {
            guard let shownIDs, index < content.tiles.count else { return true }
            return shownIDs.contains(content.tiles[index].id)
        }
        let shownCount = (0..<tileViews.count).filter(isShown).count
        let ongoingCount = (0..<tileViews.count).filter { isShown($0) && $0 < content.tiles.count && content.tiles[$0].kind.isOngoing }.count
        let layout = NotchRow.layout(windows: shownCount - ongoingCount, ongoing: ongoingCount)
        let cellsHeight = max(0, top - 22 - (content.activitiesExpanded ? 142 : 0))
        let filterChanged = placedOnce && placedShownIDs != shownIDs
        let animateSettle = filterChanged && !Motion.reduced
        var rank = 0
        for (index, tile) in tileViews.enumerated() {
            if index < content.tiles.count, content.tiles[index].kind.isOngoing { tile.updateOngoing(content.tiles[index]) }
            guard isShown(index) else {
                if tile.isHidden { continue }
                if filterChanged {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = animateSettle ? Motion.fadeDuration : 0
                        tile.animator().alphaValue = 0
                    }, completionHandler: { [weak tile] in
                        MainActor.assumeIsolated { tile?.isHidden = true }
                    })
                } else {
                    tile.isHidden = true
                }
                continue
            }
            let frame = NSRect(x: CGFloat(layout.leading(inRowWidth: Double(rect.width)) + layout.x(ofCell: rank)), y: 14,
                               width: CGFloat(NotchRow.cellWidth), height: cellsHeight)
            if tile.isHidden {
                tile.frame = frame
                tile.isHidden = false
                tile.alphaValue = 0
            }
            tile.setPosition(rank + 1, of: shownCount)
            if animateSettle, tile.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.Spring.calm.response
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    tile.animator().frame = frame
                    tile.animator().alphaValue = 1
                }
            } else {
                tile.frame = frame
                if tile.alphaValue < 1, placedOnce {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animateSettle ? Motion.fadeDuration : 0
                        tile.animator().alphaValue = 1
                    }
                }
            }
            rank += 1
        }
        placedShownIDs = shownIDs
        placedOnce = true
        if let line = layout.dividerFrame(inRowWidth: Double(rect.width), cellsMinY: 14, cellsHeight: Double(cellsHeight)) {
            divider.frame = NSRect(x: line.x, y: line.y, width: line.width, height: line.height)
            divider.isHidden = false
        } else {
            divider.isHidden = true
        }
        placeQuery(content, rect: rect, cellsMinY: 14, cellsHeight: cellsHeight, shownCount: shownCount)
        hint.stringValue = content.hint ?? ""
        hint.isHidden = content.hint == nil
        let size = hint.intrinsicContentSize
        if let island = content.fileDrop, content.drop != .none {
            // 文件那一种：三格加两耳，整块由 FileDropIslandView 画（FS-03）。
            fileIsland.isHidden = false
            fileIsland.frame = bounds
            fileIsland.update(island)
            glyph.isHidden = true
            choiceViews.forEach { $0.isHidden = true }
            hint.isHidden = true
        } else if content.drop != .none {
            fileIsland.isHidden = true
            // 落点：五个去处一排在上、一行字在下，一起居中在刘海下面那一块里。指着的那一格亮、放大一点。
            let side: CGFloat = 26, gap: CGFloat = 6
            let block = side + gap + size.height
            let bottom = max(6, (top - block) / 2)
            hint.frame = NSRect(x: (rect.width - size.width) / 2, y: bottom, width: size.width, height: size.height)
            let slot = rect.width / CGFloat(choiceViews.count)
            let showRow = !content.stripLanding && (content.drop == .offered || content.drop == .armed)
            for (index, view) in choiceViews.enumerated() {
                let chosen = content.drop == .armed && index == content.dropChoice.rawValue
                let edge = chosen ? side + 4 : side - 2
                view.frame = NSRect(x: slot * CGFloat(index) + (slot - edge) / 2,
                                    y: bottom + size.height + gap - (chosen ? 2 : -1), width: edge, height: edge)
                view.alphaValue = content.dropDisabled.contains(index) ? NotchSmallBehaviour.disabledAlpha
                    : chosen ? 1 : (content.drop == .armed ? 0.38 : 0.6)
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
            fileIsland.isHidden = true
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

extension NotchContentView {
    /// 打字筛选（LA-7）：字写在刘海左边那一段（右对齐、紧挨刘海，13 半粗，后面一个光标）；一格也没有时在格子那一块写“没有匹配的”。
    /// 左边放不下整串就留最后几个字。不用计时器：光标不闪，免得空闲时还在重画。
    fileprivate func placeQuery(_ content: NotchCanvasView.Content, rect: NSRect, cellsMinY: CGFloat, cellsHeight: CGFloat,
                                shownCount: Int) {
        let query = content.query
        let showsQuery = !query.isEmpty && content.notchHeight > 0
        queryLabel.isHidden = !showsQuery
        queryCursor.isHidden = !showsQuery
        compactView.alphaValue = showsQuery ? 0 : 1
        if showsQuery {
            let notchLeft = (rect.width - content.notchWidth) / 2
            let right = notchLeft - 8
            let room = max(0, right - CGFloat(NotchRow.edgeMargin) - 3)
            var text = query
            var width = (text as NSString).size(withAttributes: [.font: queryLabel.font as Any]).width
            var limit = query.count
            while width > room, limit > 2 {
                limit -= 1
                text = NotchRowFilter.visibleTail(of: query, limit: limit)
                width = (text as NSString).size(withAttributes: [.font: queryLabel.font as Any]).width
            }
            queryLabel.stringValue = text
            queryLabel.setAccessibilityLabel(WSL10n.text("notch.filter.label", zh: "筛选：%@", query))
            let height: CGFloat = 16
            let y = rect.height - content.notchHeight / 2 - height / 2
            queryCursor.frame = NSRect(x: right - 1.5, y: y + 1, width: 1.5, height: height - 2)
            queryLabel.frame = NSRect(x: max(CGFloat(NotchRow.edgeMargin), right - 3.5 - ceil(width) - 2), y: y,
                                      width: min(room, ceil(width) + 2), height: height)
        }
        let empty = shownCount == 0 && content.shownIDs != nil
        noMatchLabel.isHidden = !empty
        if empty {
            let size = noMatchLabel.intrinsicContentSize
            noMatchLabel.frame = NSRect(x: (rect.width - size.width) / 2, y: cellsMinY + (cellsHeight - size.height) / 2,
                                        width: size.width, height: size.height)
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

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
    /// 编程会话在跑：右耳的转圈。Core Animation 自己转，不起计时器；不在跑就拿掉。
    private let spinner = NotchSessionSpinner.makeLayer()
    /// 实时活动的量（M12）：右耳的环或不确定弧。数变了只改 strokeEnd，画法变了才重排。
    private let part = NotchProgressPartLayers()
    /// 环或弧此刻画在右耳上（放得下才画）。
    private var partShown = false
    /// 右耳上实际写的字：放不下“第 3 / 12”时换成短写法。
    private var earText: String?

    // MARK: 文件架个数（右耳）：图层自己滚、自己弹，不重画。
    private let shelfText = CATextLayer()
    private var shelfShownText: String?

    // MARK: 音量亮度两耳（左耳符号、右耳白条）。图层自己动，不重画。
    private let levelSymbol = CALayer()
    private let levelTrack = CALayer()
    private let levelFill = CALayer()
    private let levelCap = CALayer()
    private var shownLevel: NotchPanel.LevelEar?
    private var shownSymbolName: String?

    // MARK: 正在播放两耳（NP-2）：左耳封面、右耳 5 个静止取色点。图层各自带色，不重画；不画任何会动的波形。
    private let coverHost = CALayer()
    private let coverImage = CALayer()
    private let coverPlaceholder = CALayer()
    private let coverNote = CALayer()
    private let dotLayers: [CALayer] = (0..<NowPlayingEars.dotCount).map { _ in CALayer() }
    private var musicShown = false
    private var shownCoverKey: String?
    private var shownNoteSide: Double?
    /// 右耳 5 根（NP-6）：今天的静止点，或跟着声音跳 / 减少动态效果时的填充色点。暂停一律按暂停画。
    private var wave = NowPlayingWave.dots

    func setMusicWave(_ next: NowPlayingWave) {
        guard next != wave else { return }
        let modeChanged = next.mode != wave.mode
        wave = next
        guard musicShown, let (_, music) = coverEars, let slots else { return }
        CATransaction.begin()
        // 换样子（静止点 ↔ 跟着跳）沿 0.18 秒淡过去；每秒 30 次的高度直接到位，起落已经在电平里了。
        if modeChanged && !Motion.reduced { CATransaction.setAnimationDuration(NowPlayingEars.fadeSeconds) }
        else { CATransaction.setDisableActions(true) }
        layoutDots(music: music, trailing: Self.slot(slots.trailing))
        CATransaction.commit()
    }

    private static func slot(_ rect: NSRect) -> NowPlayingEars.Slot {
        NowPlayingEars.Slot(minX: Double(rect.minX), minY: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    /// 5 个点的位置、大小、颜色。跟着跳：根高 = 2.4 + 11.6 × 电平，竖直居中，全部主色；
    /// 减少动态效果：静止的填充色点；其余（没开、没权限、录不到、蓝牙 + Spotify）：主色副色交替的静止点；暂停：白 0.45。
    private func layoutDots(music: NotchPanel.MusicEar, trailing: NowPlayingEars.Slot) {
        let mode: NowPlayingWaveMode = music.paused ? .paused : (wave.mode == .paused ? .dots : wave.mode)
        let base = NowPlayingEars.dotColors(palette: music.artwork?.palette, paused: music.paused)
        let filled = mode == .live || mode == .still
        for (index, dot) in dotLayers.enumerated() {
            var box = NowPlayingEars.dotFrame(index: index, in: trailing)
            if mode == .live, index < wave.levels.count {
                let height = AudioLevelBands.rootHeight(level: wave.levels[index])
                box.y += (box.height - height) / 2
                box.height = height
            }
            dot.isHidden = false
            dot.bounds = CGRect(x: 0, y: 0, width: box.width, height: box.height)
            dot.position = CGPoint(x: box.x, y: box.y)
            dot.cornerRadius = CGFloat(min(box.width, box.height) / 2)
            let color = filled ? base[0] : base[index]
            dot.backgroundColor = NSColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b),
                                          alpha: CGFloat(color.alpha)).cgColor
        }
    }


    /// 计时器的橙色（稿 #ff9f0a）；超时的右耳字用它。
    private static let timerOrange = NSColor(srgbRed: CountdownTimerStyle.orangeRGB.0, green: CountdownTimerStyle.orangeRGB.1,
                                             blue: CountdownTimerStyle.orangeRGB.2, alpha: 1)
    private static func earFont() -> NSFont {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    }
    private static func textWidth(_ text: String) -> CGFloat {
        text.isEmpty ? 0 : ceil(NSAttributedString(string: text, attributes: [.font: earFont()]).size().width)
    }

    /// 右耳放得下什么：环（或弧）加字都放得下才画图形，放不下就退回原来的样子（音乐、拷贝的比例回到细条，不确定弧不画）；
    /// 只写个数的，放不下“第 3 / 12”就写“3/12”。
    private func resolveEar() {
        partShown = false
        earText = compact?.trailing
        guard coverEars == nil else { return }
        guard let compact, compact.leading != nil, compact.sessionPhase == nil, let slots else { return }
        let room = slots.trailing.width - CGFloat(NotchProgressPart.edgeInset) - 4
        let text = compact.trailing ?? ""
        switch compact.quantity.drawing {
        case .ring, .spinningArc:
            let need = Self.textWidth(text) + CGFloat(NotchProgressPart.reservedWidth(for: .ring))
            partShown = (text.isEmpty ? CGFloat(NotchProgressPart.ringDiameter) : need) <= room
        case .countText:
            if let full = compact.quantity.countText, text == full, Self.textWidth(text) > room,
               let short = compact.quantity.shortCountText { earText = short }
        case .none: break
        }
    }

    /// 环或弧：位置贴着右耳的右边缘、竖直居中。
    private func syncPart() {
        let quantity = partShown ? (compact?.quantity ?? .unknown) : .unknown
        if quantity.drawing != .none {
            wantsLayer = true
            if part.root.superlayer == nil { layer?.addSublayer(part.root) }
        }
        if let slots {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            part.root.position = CGPoint(x: slots.trailing.maxX - CGFloat(NotchProgressPart.edgeInset) - NotchProgressPartLayers.side / 2,
                                         y: slots.trailing.midY)
            CATransaction.commit()
        }
        part.apply(quantity, tone: compact?.progressTone ?? .playback)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        part.setAttached(window != nil)
    }

    func update(_ compact: NotchPanel.Compact?, slots: (leading: NSRect, trailing: NSRect)?) {
        self.compact = compact
        self.slots = slots
        resolveEar()
        needsDisplay = true
        syncPart()
        updateSpinner()
        syncLevel()
        syncMusic()
        syncShelfCount()
        setAccessibilityElement(compact != nil && compact?.level == nil)
        setAccessibilityRole(.staticText)
        // 过期：两耳降到 0.5；增强对比度时也靠右耳的“—”认，不只靠暗。
        alphaValue = compact?.stale == true ? CGFloat(NotchActivity.staleAlpha) : 1
        defer {
            if compact?.stale == true { setAccessibilityLabel(NotchEarText.spoken(accessibilityLabel() ?? "", stale: true)) }
        }
        if let compact {
            if let flash = compact.flash {
                setAccessibilityLabel(flash.spoken)
            } else if let music = compact.music {
                setAccessibilityLabel(music.spoken)
            } else if let spoken = compact.shelfSpoken {
                setAccessibilityLabel(spoken)
            } else if let spoken = compact.calendar?.spoken, !spoken.isEmpty {
                setAccessibilityLabel(spoken)
            } else if let leading = compact.leading {
                let joinText = WSL10n.text("notch.join", zh: "，")
                switch compact.sessionPhase {
                case .waiting?:
                    setAccessibilityLabel(leading + joinText + WSL10n.text("notch.row.waiting", zh: "在等你"))
                case .running?:
                    setAccessibilityLabel(leading + joinText + WSL10n.text("notch.row.running", zh: "在跑"))
                case .quota?:
                    let running = WSL10n.text("notch.row.running", zh: "在跑")
                    let withEar = compact.trailing.flatMap {
                        $0.isEmpty ? nil : WSL10n.text("notch.row.runningWithEar", zh: "在跑，%@", $0)
                    }
                    setAccessibilityLabel(leading + joinText + (withEar ?? running))
                case .quotaLow?:
                    setAccessibilityLabel(leading + joinText
                        + WSL10n.text("notch.row.runningQuotaLow", zh: "在跑，额度快用完了"))
                case .done?: setAccessibilityLabel(leading)
                case nil:
                    let tail = compact.trailing.flatMap { $0.isEmpty ? nil : $0 }
                    setAccessibilityLabel(tail.map { "\(leading)，\($0)" } ?? leading)
                }
            } else {
                setAccessibilityLabel(compact.count > 0
                    ? WSL10n.text("notch.folded.count", zh: "刘海里收着 %@ 扇窗口", String(compact.count))
                    : WSL10n.text("notch.folded.changed", zh: "收起的窗口有变化"))
            }
        }
    }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 这一点（本视图坐标）在正在播放的左耳或右耳上。放不下封面退回音符时也算：它还是音乐的两耳。
    func containsMusicEar(_ point: NSPoint) -> Bool {
        guard compact?.music != nil, compact?.level == nil, let slots else { return false }
        return slots.leading.contains(point) || slots.trailing.contains(point)
    }

    /// 此刻是不是画封面耳：有音乐两耳、没被音量亮度顶掉、而且封面放得下（放不下就是今天的样子）。
    private var coverEars: (side: Double, music: NotchPanel.MusicEar)? {
        guard slots != nil, compact?.level == nil, let music = compact?.music, let side = music.coverSide else { return nil }
        return (side, music)
    }

    private func prepareMusicLayers() {
        wantsLayer = true
        guard let host = layer, coverHost.superlayer == nil else { return }
        // 位置、大小、圆角、图片都直接到位；只有颜色和透明度沿 0.18 秒淡过去（见 syncMusic）。
        let still: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(),
                                         "contents": NSNull(), "hidden": NSNull()]
        coverHost.actions = still
        coverHost.anchorPoint = .zero
        coverHost.masksToBounds = true
        coverHost.cornerCurve = .continuous
        for sub in [coverImage, coverPlaceholder, coverNote] {
            sub.actions = still
            sub.anchorPoint = .zero
            coverHost.addSublayer(sub)
        }
        coverImage.contentsGravity = .resizeAspectFill
        coverImage.magnificationFilter = .linear
        coverImage.minificationFilter = .trilinear
        coverPlaceholder.backgroundColor = NSColor(white: CGFloat(NowPlayingEars.placeholderFillWhite), alpha: 1).cgColor
        host.addSublayer(coverHost)
        for dot in dotLayers {
            dot.actions = still
            dot.anchorPoint = .zero
            host.addSublayer(dot)
        }
    }

    private func hideMusicLayers() {
        guard musicShown else { return }
        coverHost.isHidden = true
        for dot in dotLayers { dot.isHidden = true }
        coverImage.contents = nil
        shownCoverKey = nil
        musicShown = false
    }

    private func noteImage(side: Double, scale: CGFloat) -> (CGImage, CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(side * 0.5), weight: .semibold)
            .applying(.init(paletteColors: [NSColor(white: CGFloat(NowPlayingEars.placeholderNoteWhite), alpha: 1)]))
        guard let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, image.size)
    }

    /// 左耳封面（没封面画占位：白 0.14 的圆角方块加白 0.6 的音符）、右耳 5 个静止点（主色副色交替）。
    /// 暂停：封面透明度 0.5、点变白 0.45，沿 0.18 秒淡过去；减少动态效果直接换。
    private func syncMusic() {
        guard let (side, music) = coverEars, let slots else { hideMusicLayers(); return }
        prepareMusicLayers()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let leading = NowPlayingEars.Slot(minX: Double(slots.leading.minX), minY: Double(slots.leading.minY),
                                          width: Double(slots.leading.width), height: Double(slots.leading.height))
        let trailing = NowPlayingEars.Slot(minX: Double(slots.trailing.minX), minY: Double(slots.trailing.minY),
                                           width: Double(slots.trailing.width), height: Double(slots.trailing.height))
        let frame = NowPlayingEars.coverFrame(in: leading, side: side)
        let animated = musicShown && !Motion.reduced
        let key = music.artwork.map { "\($0.trackKey)#\($0.fingerprint)" }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(NowPlayingEars.fadeSeconds) } else { CATransaction.setDisableActions(true) }
        coverHost.isHidden = false
        coverHost.bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        coverHost.position = CGPoint(x: frame.x, y: frame.y)
        coverHost.cornerRadius = CGFloat(NowPlayingEars.coverCorner(side: side))
        coverHost.opacity = Float(NowPlayingEars.coverAlpha(paused: music.paused))
        for sub in [coverImage, coverPlaceholder] { sub.bounds = coverHost.bounds; sub.position = .zero }
        coverImage.contentsScale = scale
        if key != shownCoverKey {
            let image = music.artwork?.makeCGImage()
            if animated, !Motion.reduced {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = NowPlayingEars.fadeSeconds
                coverImage.add(fade, forKey: "cover.fade")
            }
            coverImage.contents = image
            coverImage.isHidden = image == nil
            coverPlaceholder.isHidden = image != nil
            coverNote.isHidden = image != nil
            shownCoverKey = key
        }
        if shownNoteSide != side {
            if let (note, size) = noteImage(side: side, scale: scale) {
                coverNote.contents = note
                coverNote.contentsScale = scale
                coverNote.bounds = CGRect(origin: .zero, size: size)
                coverNote.position = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)
                shownNoteSide = side
            }
        }
        layoutDots(music: music, trailing: trailing)
        CATransaction.commit()
        musicShown = true
    }

    /// 右耳的转圈：只在编程会话“在跑”时有。位置贴着右耳的右边缘，竖直居中。
    private func updateSpinner() {
        let running = compact?.sessionPhase == .running && slots != nil
        if running, let slots {
            wantsLayer = true
            if spinner.superlayer == nil { layer?.addSublayer(spinner) }
            let side = NotchSessionSpinner.diameter
            spinner.position = CGPoint(x: slots.trailing.maxX - 6 - side / 2, y: slots.trailing.midY)
            spinner.isHidden = false
            NotchSessionSpinner.start(spinner)
        } else {
            NotchSessionSpinner.stop(spinner)
            spinner.isHidden = true
        }
    }

    private func prepareLevelLayers() {
        wantsLayer = true
        guard let host = layer else { return }
        for sub in [levelTrack, levelFill, levelCap, levelSymbol] where sub.superlayer == nil {
            sub.anchorPoint = .zero
            sub.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(), "opacity": NSNull(),
                           "contents": NSNull(), "backgroundColor": NSNull()]
            host.addSublayer(sub)
        }
    }

    private func hideLevelLayers() {
        for sub in [levelTrack, levelFill, levelCap, levelSymbol] { sub.isHidden = true; sub.removeAllAnimations() }
        shownLevel = nil
        shownSymbolName = nil
    }

    /// 把一层挪到新位置：平时沿 pop 弹过去，减少动态效果直接到位。
    private func place(_ layer: CALayer, bounds: CGRect, position: CGPoint, radius: CGFloat, animated: Bool) {
        let from = layer.presentation() ?? layer
        let moves: [(String, Any, Any)] = [
            ("bounds", NSValue(rect: from.bounds), NSValue(rect: bounds)),
            ("position", NSValue(point: from.position), NSValue(point: position)),
            ("cornerRadius", from.cornerRadius, radius),
        ]
        layer.bounds = bounds
        layer.position = position
        layer.cornerRadius = radius
        layer.removeAllAnimations()
        guard animated, !Motion.reduced else { return }
        for (key, start, end) in moves where !(start as AnyObject).isEqual(end) {
            let animation = Motion.spring(.pop, keyPath: key)
            animation.fromValue = start
            animation.toValue = end
            layer.add(animation, forKey: "level." + key)
        }
    }

    private func levelSymbolImage(_ name: String, kind: NotchPanel.LevelKind) -> (CGImage, CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let fallback: String
        switch kind {
        case .volume: fallback = "speaker.wave.2.fill"
        case .brightness: fallback = "sun.max.fill"
        case .keyboardLight: fallback = "light.max"
        }
        guard let image = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil))?
            .withSymbolConfiguration(configuration) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, image.size)
    }

    /// 左耳符号、右耳条。同一种里数值、符号、拉长变了就原地换（条沿 pop 一格接一格扫过去）；
    /// 到头再按条拉长、符号顺着挪，回来时 pop 弹回；减少动态效果不拉长，条的那一头从白 0.6 亮到 1。
    private func syncLevel() {
        guard let level = compact?.level, let slots else {
            if shownLevel != nil { hideLevelLayers() }
            return
        }
        prepareLevelLayers()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let animated = shownLevel?.kind == level.kind
        let bar = NotchLevelEars.bar(slotMinX: Double(slots.trailing.minX), slotHeight: Double(slots.trailing.height),
                                     value: level.value, stretch: level.stretch)
        let originY = slots.trailing.minY
        let fillWidth = CGFloat(bar.fillWidth)
        let height = CGFloat(bar.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        levelTrack.backgroundColor = NSColor.white.withAlphaComponent(NotchLevelEars.trackAlpha(increasedContrast: contrast)).cgColor
        levelFill.backgroundColor = NSColor.white.withAlphaComponent(NotchLevelEars.fillAlpha).cgColor
        levelCap.backgroundColor = NSColor.white.cgColor
        levelCap.opacity = 0
        for sub in [levelTrack, levelFill, levelSymbol] { sub.isHidden = false }
        levelCap.isHidden = false
        place(levelTrack, bounds: CGRect(x: 0, y: 0, width: bar.width, height: bar.height),
              position: CGPoint(x: bar.x, y: originY + bar.y), radius: height / 2, animated: animated)
        place(levelFill, bounds: CGRect(x: 0, y: 0, width: fillWidth, height: bar.height),
              position: CGPoint(x: slots.trailing.minX + NotchLevelEars.barNotchGap, y: originY + bar.y),
              radius: min(height / 2, fillWidth / 2), animated: animated)
        levelFill.isHidden = fillWidth < 0.5
        // 符号：喇叭身子不动，声波往右长，所以按左边对齐；拉长时顺着条的方向挪 ¼。
        if level.symbol != shownSymbolName || level.kind != shownLevel?.kind,
           let (image, size) = levelSymbolImage(level.symbol, kind: level.kind) {
            levelSymbol.contents = image
            levelSymbol.contentsScale = scale
            levelSymbol.bounds = CGRect(origin: .zero, size: size)
            shownSymbolName = level.symbol
        }
        let symbolSize = levelSymbol.bounds.size
        place(levelSymbol, bounds: levelSymbol.bounds,
              position: CGPoint(x: slots.leading.minX + CGFloat(NotchLevelEars.symbolInset + NotchLevelEars.symbolOffset(stretch: level.stretch)),
                                y: slots.leading.midY - symbolSize.height / 2),
              radius: 0, animated: animated)
        levelSymbol.opacity = level.dimmed ? 0.35 : 1
        CATransaction.commit()
        // 减少动态效果：到头再按，条的那一头亮一下（上头是条尾，下头是条头的小圆点）。
        if Motion.reduced, level.edge != nil, level.edgePushes != shownLevel?.edgePushes {
            if level.edge == .upper, fillWidth >= 0.5 {
                flash(levelFill)
            } else {
                levelCap.bounds = CGRect(x: 0, y: 0, width: height, height: height)
                levelCap.cornerRadius = height / 2
                levelCap.position = CGPoint(x: level.edge == .upper ? CGFloat(bar.maxX) - height : CGFloat(bar.x),
                                            y: originY + bar.y)
                flash(levelCap)
            }
        }
        shownLevel = level
    }

    private func flash(_ layer: CALayer) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = NotchLevelEars.reducedFlashFrom
        animation.toValue = 1.0
        animation.duration = NotchLevelEars.reducedFlashSeconds
        layer.opacity = layer === levelCap ? 0 : 1
        layer.add(animation, forKey: "level.flash")
    }

    /// 做完：右耳一个绿色对勾。
    private func drawDoneMark(in slot: NSRect) {
        let side: CGFloat = 14
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [.systemGreen]))
        NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)?
            .draw(in: NSRect(x: slot.maxX - side - 6, y: slot.midY - side / 2, width: side, height: side))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let compact, let slots else { return }
        if compact.level != nil { return }
        if let flash = compact.flash {
            let tint = Self.flashColor(flash.tone)
            drawEar("", symbol: flash.symbol, ring: nil, in: slots.leading, align: .left, tint: tint)
            let percentage = Self.flashPercentageLayout(flash, in: slots.trailing, color: tint)
            percentage.text.draw(at: percentage.frame.origin)
            return
        }
        if coverEars != nil {
            // 封面耳：封面和点在图层上；有收起的窗口时，信息点照旧画。
            if compact.count > 0 {
                compact.dotTone.color.setFill()
                NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
            }
            return
        }
        if let leading = compact.leading {
            let ring = compact.progressStyle == .ring ? (compact.progress ?? 0, compact.progressTone) : nil
            let timerEar = compact.progressTone == .timer || compact.progressTone == .timerPaused
                || compact.progressTone == .calendar || compact.progressTone == .calendarJoin || compact.shelfSpoken != nil
            drawEar(timerEar ? "" : leading, symbol: compact.leadingSymbol, ring: ring, in: slots.leading, align: .left)
            if compact.progressTone == .calendarJoin {
                // 开始后能加入：左耳满环，右耳一枚绿色摄像机，不写字。
                drawEar("", symbol: "video.fill", ring: nil, in: slots.trailing, align: .right, tint: .systemGreen)
                if compact.count > 0 {
                    compact.dotTone.color.setFill()
                    NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
                }
                return
            }
            // 编程会话：在跑是转圈（子图层）、等你是橙色的字、做完是对勾。
            // 活动的量：环（或弧）是子图层，字让出它的位置。
            drawEar(compact.shelfSpoken != nil ? "" : (earText ?? ""), symbol: nil, ring: nil, in: slots.trailing, align: .right,
                    color: (compact.sessionPhase == .waiting || compact.sessionPhase == .quotaLow) ? .systemOrange
                        : (compact.progressTone == .timerPaused ? NSColor.white.withAlphaComponent(0.92 * CGFloat(CountdownTimerStyle.pausedAlpha))
                           : (compact.progressTone == .timer && (earText ?? "").hasPrefix("+") ? Self.timerOrange : nil)),
                    trailingInset: partShown ? CGFloat(NotchProgressPart.reservedWidth(for: compact.quantity.drawing)) : 0)
            if compact.sessionPhase == .done { drawDoneMark(in: slots.trailing) }
            if let progress = barFraction {
                drawProgress(progress, in: slots.trailing)
            }
            if compact.count > 0 {
                compact.dotTone.color.setFill()
                NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
            }
            return
        }
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

    /// 文件架个数：右耳一个文字图层。变了滚到新值（0.28 秒），变多时右耳再弹一下（pop 0.30 / 0.75）；减少动态效果直接换。
    private func syncShelfCount() {
        guard let compact, compact.shelfSpoken != nil, compact.level == nil, let slots, let text = compact.trailing else {
            shelfText.isHidden = true
            shelfShownText = nil
            return
        }
        wantsLayer = true
        guard let host = layer else { return }
        let font = Self.earFont()
        let height = ceil(font.ascender - font.descender + font.leading)
        let width = max(0, slots.trailing.width - 12)
        let frame = CGRect(x: slots.trailing.maxX - 6 - width, y: slots.trailing.midY - height / 2, width: width, height: height)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        func style(_ layer: CATextLayer, _ string: String) {
            layer.font = font
            layer.fontSize = font.pointSize
            layer.alignmentMode = .right
            layer.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            layer.contentsScale = scale
            layer.frame = frame
            layer.string = string
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if shelfText.superlayer == nil { host.addSublayer(shelfText) }
        shelfText.isHidden = false
        let old = shelfShownText
        style(shelfText, text)
        CATransaction.commit()
        shelfShownText = text
        guard let old, old != text, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let roll = NotchShelfEars.roll(from: Int(old), to: Int(text) ?? 0)
        if roll != .none {
            // 变多：旧值往上顶出去、新值从下面上来；变少反过来。
            let travel: CGFloat = roll == .up ? 10 : -10
            let outgoing = CATextLayer()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            style(outgoing, old)
            host.addSublayer(outgoing)
            CATransaction.commit()
            func slide(from: CGFloat, to: CGFloat, fadeFrom: Float, fadeTo: Float) -> CAAnimationGroup {
                let move = CABasicAnimation(keyPath: "transform.translation.y")
                move.fromValue = from; move.toValue = to
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = fadeFrom; fade.toValue = fadeTo
                let group = CAAnimationGroup()
                group.animations = [move, fade]
                group.duration = NotchShelfEars.rollDuration
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                return group
            }
            CATransaction.begin()
            CATransaction.setCompletionBlock { outgoing.removeFromSuperlayer() }
            outgoing.add(slide(from: 0, to: travel, fadeFrom: 1, fadeTo: 0), forKey: "roll")
            outgoing.opacity = 0
            CATransaction.commit()
            shelfText.add(slide(from: -travel, to: 0, fadeFrom: 0, fadeTo: 1), forKey: "roll")
        }
        if NotchShelfEars.pops(from: Int(old), to: Int(text) ?? 0) {
            let stiffness = pow(2 * Double.pi / NotchShelfEars.popResponse, 2)
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 1.28; spring.toValue = 1
            spring.mass = 1
            spring.stiffness = stiffness
            spring.damping = 2 * NotchShelfEars.popDamping * stiffness.squareRoot()
            spring.duration = spring.settlingDuration
            shelfText.add(spring, forKey: "pop")
        }
    }

    /// 右耳下面那条细条的比例：音量、亮度一直是它；活动的比例放不下环加字时退回到它（和原来一样）。
    private var barFraction: Double? {
        if coverEars != nil { return nil }
        if let progress = compact?.progress, compact?.progressStyle == .bar { return progress }
        if compact?.leading != nil, !partShown, compact?.quantity.drawing == .ring { return compact?.quantity.fractionValue }
        return nil
    }

    /// 电量那一下的颜色：高于 20% 绿、20% 及以下红、低电量模式黄（系统色，随浅深色与对比度）。
    static func flashColor(_ tone: PowerFlashTone) -> NSColor {
        switch tone {
        case .green: return .systemGreen
        case .red: return .systemRed
        case .yellow: return .systemYellow
        }
    }

    /// 0…100% is one compact value. Keep every digit and the percent sign within the 34pt ear.
    static func flashPercentageLayout(_ flash: PowerFlash, in slot: NSRect, color: NSColor) -> (text: NSAttributedString, frame: NSRect) {
        let base = earFont()
        let font = NSFont(descriptor: base.fontDescriptor, size: 10)
            ?? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let text = NSAttributedString(string: flash.trailing, attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        return (text, NSRect(x: slot.maxX - 2 - size.width, y: slot.midY - size.height / 2,
                             width: size.width, height: size.height))
    }

    private func drawEar(_ text: String, symbol: String?, ring: (progress: Double, tone: NotchPanel.Compact.ProgressTone)?,
                         in slot: NSRect, align: NSTextAlignment, color: NSColor? = nil, trailingInset: CGFloat = 0,
                         tint: NSColor? = nil) {
        guard !text.isEmpty || symbol != nil || ring != nil else { return }
        var x = slot.minX + 6
        let side: CGFloat = 14
        if let ring {
            let box = CGFloat(NotchFocusRing.viewport)
            drawRing(ring.progress, tone: ring.tone, in: NSRect(x: x, y: slot.midY - box / 2, width: box, height: box))
            x += box + 4
        } else if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(tint.map { .init(pointSize: 12, weight: .semibold).applying(.init(paletteColors: [$0])) }
                                     ?? .init(pointSize: 12, weight: .semibold)) {
            image.draw(in: NSRect(x: align == .right ? slot.maxX - side - 6 : x, y: slot.midY - side / 2, width: side, height: side))
            if align != .right { x += side + 4 }
        }
        let rounded = Self.earFont()
        let string = NSAttributedString(string: text, attributes: [
            .font: rounded, .foregroundColor: color ?? NSColor.white.withAlphaComponent(0.92),
        ])
        let size = string.size()
        let maxWidth = max(0, slot.width - (x - slot.minX) - 6 - trailingInset)
        let drawX = align == .right ? slot.maxX - min(size.width, maxWidth) - 6 - trailingInset : x
        let hasBar = barFraction != nil
        let textY = slot.midY - size.height / 2 + (hasBar ? 2 : 0)
        string.draw(with: NSRect(x: drawX, y: textY, width: min(size.width, maxWidth), height: size.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawProgress(_ progress: Double, in slot: NSRect) {
        let width = min(32, max(18, slot.width - 12))
        let bar = NSRect(x: slot.maxX - 6 - width, y: slot.minY + 4, width: width, height: 3.5)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.75, yRadius: 1.75).fill()
        var fill = bar
        fill.size.width = max(3.5, bar.width * CGFloat(min(1, max(0, progress))))
        switch compact?.progressTone {
        case .focus: NSColor.systemRed.setFill()
        case .playback, .rest: NSColor.systemGreen.setFill()
        case .accent, nil: NSColor.controlAccentColor.setFill()
        case .timer?, .timerPaused?: Self.timerOrange.setFill()
        case .calendar?, .calendarJoin?: CalendarEarImage.color(compact?.calendar?.colorRGB).setFill()
        }
        NSBezierPath(roundedRect: fill, xRadius: 1.75, yRadius: 1.75).fill()
    }

    /// 番茄钟的进度环：16 pt 视口、半径 6.5、线宽 2.2；底环白 18%，专注红、休息绿，从正上方顺时针走。
    private func drawRing(_ progress: Double, tone: NotchPanel.Compact.ProgressTone, in box: NSRect) {
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = CGFloat(NotchFocusRing.radius)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = CGFloat(NotchFocusRing.lineWidth)
        NSColor.white.withAlphaComponent(NotchFocusRing.trackWhiteAlpha).setStroke()
        track.stroke()
        let value = min(1, max(0, progress))
        if tone == .calendar || tone == .calendarJoin,
           let glyph = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            // 稿：环里一枚缩小的日历符号。
            let g = glyph.size
            glyph.draw(in: NSRect(x: center.x - g.width / 2, y: center.y - g.height / 2, width: g.width, height: g.height))
        }
        if tone == .timerPaused {
            // 暂停：环降到 0.5，环中间两道竖线。
            let bars = NSBezierPath()
            for dx in [CGFloat(-1.8), 1.8] { bars.move(to: NSPoint(x: center.x + dx, y: center.y - 2.4)); bars.line(to: NSPoint(x: center.x + dx, y: center.y + 2.4)) }
            bars.lineWidth = 1.5; bars.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.92).setStroke(); bars.stroke()
        }
        guard value > 0 else { return }
        let rgb: (Double, Double, Double)
        switch tone {
        case .timer, .timerPaused: rgb = CountdownTimerStyle.orangeRGB
        case .calendar, .calendarJoin:
            let c = CalendarEarImage.color(compact?.calendar?.colorRGB).usingColorSpace(.sRGB) ?? .systemBlue
            rgb = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        case .rest: rgb = NotchFocusRing.restRGB
        default: rgb = NotchFocusRing.focusRGB
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(value), clockwise: true)
        arc.lineWidth = CGFloat(NotchFocusRing.lineWidth)
        arc.lineCapStyle = .round
        NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: tone == .timerPaused ? CGFloat(CountdownTimerStyle.pausedAlpha) : 1).setStroke()
        arc.stroke()
    }
}

extension NotchInfoDot {
    /// 信息点在岛里的位置：右 10、下 8，直径 8。
    static func rect(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.maxX - CGFloat(trailingInset + diameter), y: bounds.minY + CGFloat(bottomInset),
               width: CGFloat(diameter), height: CGFloat(diameter))
    }
}

extension NotchInfoDot.Tone {
    var color: NSColor {
        switch self {
        case .accent: return .controlAccentColor
        case .volume: return .systemBlue
        case .playback: return .systemGreen
        case .focus: return NSColor(srgbRed: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255, alpha: 1)
        case .rest: return NSColor(srgbRed: 0x5F / 255, green: 0xD3 / 255, blue: 0x8A / 255, alpha: 1)
        }
    }
}

/// 最小形（M13）：黑色小胶囊，里面是语气色圆点，有比例时圆点外绕一圈 2pt 的弧。
/// 读屏当按钮读（“正在进行：标题”），点一下和紧凑互换。鼠标由画布统一接，这里不挡。
final class NotchMinimumView: NSView {
    private(set) var shapeID: String
    var onSelect: ((String) -> Void)?
    private let dot = CALayer()
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()

    init(shape: NotchMinimumShape) {
        shapeID = shape.id
        super.init(frame: shape.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerCurve = .continuous
        let diameter = NotchMinimalPresentation.arcDiameter
        let line = NotchMinimalPresentation.arcLineWidth
        let ring = CGMutablePath()
        ring.addArc(center: CGPoint(x: diameter / 2, y: diameter / 2), radius: (diameter - line) / 2,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for layer in [track, arc] {
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.path = ring
            layer.fillColor = nil
            layer.lineWidth = line
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        track.lineCap = .butt
        track.strokeColor = NSColor.white.withAlphaComponent(CGFloat(NotchProgressPart.trackWhiteAlpha)).cgColor
        dot.bounds = CGRect(x: 0, y: 0, width: NotchMinimalPresentation.dotDiameter, height: NotchMinimalPresentation.dotDiameter)
        dot.cornerRadius = NotchMinimalPresentation.dotDiameter / 2
        self.layer?.addSublayer(dot)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ shape: NotchMinimumShape) {
        shapeID = shape.id
        setAccessibilityLabel(shape.label)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = shape.frame.height / 2
        let center = CGPoint(x: shape.frame.width / 2, y: shape.frame.height / 2)
        dot.position = center
        track.position = center
        arc.position = center
        let color = shape.tone.color.cgColor
        dot.backgroundColor = color
        arc.strokeColor = color
        if let fraction = shape.fraction {
            track.isHidden = false
            arc.isHidden = false
            arc.strokeEnd = CGFloat(fraction)
        } else {
            track.isHidden = true
            arc.isHidden = true
        }
        CATransaction.commit()
    }

    func select() { onSelect?(shapeID) }
    override func accessibilityPerformPress() -> Bool { select(); return true }
}

/// 被挡住的提醒留下的点。不把那一句补说一遍。
final class NotchSecondaryMark: NSView {
    var visible = false {
        didSet { guard visible != oldValue else { return }; needsDisplay = true }
    }
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard visible else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
    }
}

/// 内容进场的显示器时钟代理：CADisplayLink 强引用 target，这里只弱引用画布。回调在主线程的 run loop 上。
private final class ContentWatchLinkProxy: NSObject {
    weak var owner: NotchCanvasView?
    init(owner: NotchCanvasView) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        guard let owner = owner else { link.invalidate(); return }
        MainActor.assumeIsolated { owner.contentWatchStep() }
    }
}

/// 提醒样式：刘海下面一行，App 图标、窗口新标题、App 名字。
final class NotchAlertView: NSView {
    private var alert: NotchPanel.Alert?
    private var demoView: NotchDemoView?
    private var demoTip: CoachTip?

    /// 倒数大数字放在自己的文字图层里：每秒原地换字，不跟整块一起重画。两层轮流顶替，不用随换随删。
    private let earLayers = [CATextLayer(), CATextLayer()]
    private var earActive = 0
    private var earShown: String?
    private static let earMargin: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }
    private func setUp() {
        wantsLayer = true
        for layer in earLayers {
            layer.opacity = 0
            layer.alignmentMode = .right
            layer.isWrapped = false
            layer.actions = ["opacity": NSNull(), "contents": NSNull(), "string": NSNull(), "bounds": NSNull(), "position": NSNull()]
            self.layer?.addSublayer(layer)
        }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in earLayers { layer.contentsScale = scale }
    }

    /// 等宽圆体大数字（稿：离开就锁）：1 和 10 一样宽，换数字时不挪位置。
    static func earAttributed(_ ear: String, red: Bool) -> NSAttributedString {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        return NSAttributedString(string: ear, attributes: [.font: font, .foregroundColor: red ? NSColor.systemRed : NSColor.white])
    }

    private func earFrame(for text: NSAttributedString) -> CGRect {
        let size = text.size()
        let width = ceil(size.width), height = ceil(size.height)
        return CGRect(x: bounds.width - Self.earMargin - width, y: (bounds.height - height) / 2, width: width, height: height)
    }

    /// 倒数数字变了：旧字淡出 0.10 下移 2 点，新字从上 2 点淡入并 pop 0.9→1；减少动态效果只交叉淡化 0.18。
    private func syncEar(_ alert: NotchPanel.Alert?) {
        let ear = (alert?.peek == nil && alert?.demo == nil) ? alert?.ear.flatMap { $0.isEmpty ? nil : $0 } : nil
        let previous = earShown
        earShown = ear
        let outgoing = earLayers[earActive]
        guard let ear else {
            for layer in earLayers { layer.removeAllAnimations(); layer.opacity = 0 }
            return
        }
        let text = Self.earAttributed(ear, red: alert?.earRed ?? false)
        if previous == nil {
            outgoing.removeAllAnimations()
            outgoing.string = text
            outgoing.frame = earFrame(for: text)
            outgoing.opacity = 1
            return
        }
        // 字没变（只是提醒被重放）就不动。
        if (outgoing.string as? NSAttributedString)?.isEqual(to: text) == true { outgoing.frame = earFrame(for: text); return }
        let incoming = earLayers[1 - earActive]
        earActive = 1 - earActive
        incoming.removeAllAnimations()
        outgoing.removeAllAnimations()
        incoming.string = text
        incoming.frame = earFrame(for: text)
        incoming.opacity = 1
        outgoing.opacity = 0
        let plan = Motion.DigitSwap.plan(reduced: Motion.reduced)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0; fadeIn.toValue = 1; fadeIn.duration = plan.inDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        incoming.add(fadeIn, forKey: "ear.in")
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1; fadeOut.toValue = 0; fadeOut.duration = plan.outDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        outgoing.add(fadeOut, forKey: "ear.out")
        guard plan.shift > 0 else { return }
        // 图层坐标 y 向上：旧字往下（−2），新字从上（+2）落回。
        let drop = CABasicAnimation(keyPath: "transform.translation.y")
        drop.fromValue = 0; drop.toValue = -plan.shift; drop.duration = plan.outDuration
        drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
        outgoing.add(drop, forKey: "ear.drop")
        let settle = Motion.spring(.pop, keyPath: "transform.translation.y")
        settle.fromValue = plan.shift; settle.toValue = 0
        incoming.add(settle, forKey: "ear.settle")
        let pop = Motion.spring(.pop, keyPath: "transform.scale")
        pop.fromValue = plan.popFrom; pop.toValue = 1
        incoming.add(pop, forKey: "ear.pop")
    }

    func update(_ alert: NotchPanel.Alert?) {
        self.alert = alert
        syncEar(alert)
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
        if let alert {
            let ear = alert.ear.map { "，\($0)" } ?? ""
            let action = alert.actionLabel.map { WSL10n.text("notch.alert.action", zh: "，点一下%@", $0) } ?? ""
            if let peek = alert.peek {
                setAccessibilityLabel(NowPlayingPeek.spoken(title: peek.title, artist: peek.artist))
            } else {
                setAccessibilityLabel("\(alert.subtitle)：\(alert.title)\(ear)\(action)")
            }
        }
    }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// §6-4：图标 24，四周 14，不留额头。
    static func iconRect(in bounds: NSRect) -> NSRect {
        NSRect(x: 14, y: (bounds.height - 24) / 2, width: 24, height: 24)
    }

    /// 窗口提醒里的图标此刻在屏幕上的位置；没有图标（教手势、没显示）就是 nil。
    var iconScreenRect: NSRect? {
        guard let alert, alert.demo == nil, alert.icon != nil, let window, !isHidden else { return nil }
        let rect = Self.iconRect(in: bounds)
        return window.convertToScreen(convert(rect, to: nil))
    }

    /// 卡住提示里新的那排键帽按一下（见 CoachEcho）。
    func echoKeys() { demoView?.echoKeys() }

    override func layout() {
        super.layout()
        if earShown != nil, let text = earLayers[earActive].string as? NSAttributedString {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            earLayers[earActive].frame = earFrame(for: text)
            CATransaction.commit()
        }
        demoView?.frame = NSRect(x: 14, y: (bounds.height - NotchDemoView.size.height) / 2,
                                 width: NotchDemoView.size.width, height: NotchDemoView.size.height)
    }

    /// 换歌一瞥：一行，歌名 13 半粗白，空 6，歌手 11 取封面字色；整行在宽度里居中，太长从尾巴截。
    private func drawPeek(_ peek: NotchPanel.PeekLine) {
        let margin = CGFloat(NowPlayingPeek.sideMargin)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let line = NSMutableAttributedString(string: peek.title, attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(NowPlayingPeek.titleSize), weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        if !peek.artist.isEmpty {
            // 稿的“空 6”：1 点的空格加 6 点字距，宽度约 6。
            line.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: 1), .kern: CGFloat(NowPlayingPeek.gap), .paragraphStyle: paragraph]))
            line.append(NSAttributedString(string: peek.artist, attributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(NowPlayingPeek.artistSize), weight: .medium),
                .foregroundColor: peek.artistColor ?? NSColor.white.withAlphaComponent(0.6), .paragraphStyle: paragraph]))
        }
        let height = ceil(line.size().height)
        line.draw(with: NSRect(x: margin, y: (bounds.height - height) / 2, width: max(0, bounds.width - margin * 2), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let alert else { return }
        if let peek = alert.peek { drawPeek(peek); return }
        let margin: CGFloat = 14
        let iconRect = Self.iconRect(in: bounds)
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
        var width = max(0, bounds.width - textX - margin)
        if let label = alert.actionLabel, !label.isEmpty {
            // 绿色小按钮（稿：74 × 26，圆头，摄像机加字）。点整条提醒都是同一件事。
            let pill = NSRect(x: bounds.width - margin - 74, y: (bounds.height - 26) / 2, width: 74, height: 26)
            NSColor(srgbRed: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 13, yRadius: 13).fill()
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
            let glyph = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [.white])))
            let glyphWidth = glyph?.size.width ?? 0
            let gap: CGFloat = glyph == nil ? 0 : 4
            let total = glyphWidth + gap + ceil(text.size().width)
            var x = pill.midX - total / 2
            if let glyph {
                glyph.draw(in: NSRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
                x += glyphWidth + gap
            }
            text.draw(at: NSPoint(x: x, y: pill.midY - text.size().height / 2))
            width = max(0, width - 74 - 10)
        }
        if let ear = alert.ear, !ear.isEmpty {
            // 数字本身画在 earLayers 里（原地换字）；这里只给主句、副句让出位置。
            let size = Self.earAttributed(ear, red: alert.earRed).size()
            width = max(0, width - ceil(size.width) - 10)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        // 主句里的设备名、App 名从中间省略（“Aaron…iPhone”）；副句仍从尾部省略。
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingMiddle
        let title = NSAttributedString(string: alert.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
            .paragraphStyle: titleParagraph,
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

/// 左段窗口和右段正在进行的之间那一条竖线：1pt、白 0.2。只是一道线，读屏不念、指针穿过。
final class NotchRowDivider: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(NotchRow.dividerWhite)).cgColor
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 展开后的一格：窗口的画面（没有画面就放大 App 图标）、左上角标明它是哪一种、右上角有变化的点、App 图标和标题。
/// 点一下回到它该在的地方。卡片圆角 14：外框 28 减去边距 14（HIG：同心）。
/// 左段收着的一格能拖出刘海放回卷轴（SS-04）。enabled：这一格现在能不能拖；moved：拖着的指针位置（Cocoa 屏幕坐标）；
/// finished：松手（point = nil 是作废）。
struct NotchTileDragOut {
    var enabled: @MainActor (CGWindowID) -> Bool
    var moved: @MainActor (CGWindowID, CGPoint) -> Void
    var finished: @MainActor (CGWindowID, CGPoint?) -> Void
}

final class NotchTileView: NSView {
    /// 点一下：带上画面此刻在屏幕上的位置（窗口从这里飞回去）。
    var onClick: ((NSRect?) -> Void)?
    /// 点在右下角那个 24 点的小键上（音乐的播放 / 暂停）。
    var onAccessory: (() -> Void)?
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
            fade.duration = Motion.fadeDuration
            layer?.add(fade, forKey: "snapshot")
        }
        needsDisplay = true
    }
    private var hovering = false { didSet { needsDisplay = true } }
    private var dwell: Timer?
    /// SS-04：左段收着的一格按下、拖、松手的判定（Core/StripNotchTileDrag）。
    private var drag = StripNotchTileDrag()
    /// SS-04：拖出刘海放回卷轴的口子，NotchController 在卷轴接上刘海时设；nil 时这一格和从前一样。
    static var dragOut: NotchTileDragOut?
    /// 键盘焦点亮在这一格上（M07）：放大 1.1 倍、上移 4 点、白色描边。指针一进来由 NotchPanel 先熄掉。
    private(set) var keyboardFocused = false

    init(tile: NotchTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        describe()
        syncSpinner()
        syncQuantity()
    }

    /// 提示和读屏念的话。竖线右边的格子念整句（“项目，在等你”），不加动词。
    private func describe() {
        if let ongoing = tile.ongoing {
            toolTip = ongoing.subtitle.isEmpty ? tile.title : "\(tile.title)\n\(ongoing.subtitle)"
            setAccessibilityLabel(ongoing.spoken)
            alphaValue = ongoing.isStale ? CGFloat(NotchActivity.staleAlpha) : 1
        } else {
            toolTip = "\(tile.title)\n\(tile.parked != nil ? Self.kindName(tile.kind) : (tile.place ?? Self.kindName(tile.kind)))"
            if let parked = tile.parked {
                setAccessibilityLabel(parked.spoken(title: tile.title))
            } else {
                setAccessibilityLabel("\(Self.verb(tile.kind)) \(NotchFocusController.label(for: tile.title))")
            }
        }
    }

    /// 正在进行的格内容变了（会话换了状态、曲名变了）：原地换，不重建格子。
    func updateOngoing(_ next: NotchTile) {
        guard next.kind.isOngoing, next.id == tile.id, next.ongoingSignature != tile.ongoingSignature else { return }
        tile = next
        describe()
        syncSpinner()
        syncQuantity()
        needsDisplay = true
    }

    /// 量变了（同一种画法）：只改数字和环的终点。画法不同不会走到这里（签名变了，整格换内容）。
    func setQuantity(_ quantity: NotchActivity.Quantity, text: String?) {
        guard tile.ongoing != nil, tile.ongoing?.quantity != quantity || tile.ongoing?.quantityText != text else { return }
        tile.ongoing?.quantity = quantity
        tile.ongoing?.quantityText = text
        syncQuantity()
        needsDisplay = true
    }

    /// 右上角的量（M12）：比例是环加数字，只有个数是字，不确定是转着的弧。环和弧是子图层，Core Animation 自己转。
    private let part = NotchProgressPartLayers()
    private func syncQuantity() {
        let quantity = tile.ongoing?.quantity ?? .unknown
        if quantity.drawing != .none, part.root.superlayer == nil { layer?.addSublayer(part.root) }
        placePart()
        part.apply(quantity, tone: .playback)
        // 读屏的“值”随进度变；标签（“项目，正在下载”）不跟着变。
        setAccessibilityValue(tile.ongoing?.quantityText)
    }
    private func placePart() {
        let side = NotchProgressPartLayers.side
        CATransaction.begin(); CATransaction.setDisableActions(true)
        part.root.position = CGPoint(x: bounds.width - 10 - side / 2, y: bounds.height - 10 - side / 2)
        CATransaction.commit()
    }

    /// 会话在跑：格子右上角转圈。Core Animation 自己转，不起计时器；格子离开屏幕就停。
    private let spinner = NotchSessionSpinner.makeLayer()
    private func syncSpinner() {
        let running = tile.ongoing?.phase == .running
        if running {
            if spinner.superlayer == nil { layer?.addSublayer(spinner) }
            placeSpinner()
            spinner.isHidden = false
            if window != nil { NotchSessionSpinner.start(spinner) }
        } else {
            NotchSessionSpinner.stop(spinner)
            spinner.isHidden = true
        }
    }
    private func placeSpinner() {
        let side = NotchSessionSpinner.diameter
        spinner.position = CGPoint(x: bounds.width - 10 - side / 2, y: bounds.height - 10 - side / 2)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NotchSessionSpinner.stop(spinner) } else if tile.ongoing?.phase == .running { NotchSessionSpinner.start(spinner) }
        part.setAttached(window != nil)
    }

    /// 读屏念“第几个，共几个”（和焦点挪动时的播报同一个说法）。
    func setPosition(_ index: Int, of count: Int) {
        setAccessibilityHelp(WSL10n.text("notch.alert.index", zh: "第 %@ 个，共 %@ 个", String(index + 1), String(count)))
    }

    /// 亮起或熄灭键盘焦点。`bump` 不为空：到头了，朝那个方向轻轻顶 6 点再弹回。
    func setFocused(_ focused: Bool, bump: FocusNavigator.Direction? = nil, animated: Bool = true) {
        let was = keyboardFocused
        keyboardFocused = focused
        if focused != was { needsDisplay = true }
        layer?.zPosition = focused ? 1 : 0
        guard let layer else { return }
        let rest = focusTransform(focused: focused, bump: nil)
        if let bump, focused, animated, !Motion.reduced {
            // 模型值落在原位，动画从“顶出去”的位置弹回来。
            layer.removeAnimation(forKey: "transform")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = rest
            CATransaction.commit()
            let animation = Motion.spring(.flyOut, keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: focusTransform(focused: true, bump: bump))
            animation.toValue = NSValue(caTransform3D: rest)
            layer.add(animation, forKey: "transform")
            return
        }
        if animated {
            layer.springTransform(rest, .calm, reduced: Motion.reduced)
        } else {
            layer.removeAnimation(forKey: "transform")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = rest
            CATransaction.commit()
        }
    }

    /// 绕格子中心放大再上抬；NSView 的图层锚点不在中心，平移由 NotchFocusController.Style 按锚点补回。
    private func focusTransform(focused: Bool, bump: FocusNavigator.Direction?) -> CATransform3D {
        let anchor = layer?.anchorPoint ?? .zero
        let t = NotchFocusController.Style.transform(
            width: Double(bounds.width), height: Double(bounds.height),
            pivotX: Double(anchor.x * bounds.width), pivotY: Double(anchor.y * bounds.height),
            focused: focused, bump: bump)
        return CATransform3DScale(CATransform3DMakeTranslation(CGFloat(t.translationX), CGFloat(t.translationY), 0),
                                  CGFloat(t.scale), CGFloat(t.scale), 1)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed, spinner.superlayer != nil { placeSpinner() }
        if changed, part.root.superlayer != nil { placePart() }
        if changed, keyboardFocused { setFocused(true, animated: false) }
    }

    /// 键盘上的 Return：和指针点一下是同一条路（带上画面此刻的位置，窗口从这里飞回去）。
    func activateFromKeyboard() {
        let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
        onClick?(picture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 点下去会发生什么（和菜单里的说法一致）。
    static func verb(_ kind: NotchTile.Kind) -> String {
        switch kind {
        case .tucked: return WSL10n.text("notch.verb.putBack", zh: "放回")
        case .strip, .thumbnail: return WSL10n.text("notch.verb.unroll", zh: "展开")
        case .slideOver: return WSL10n.text("notch.verb.pullOut", zh: "拉出")
        case .carried: return WSL10n.text("notch.verb.returnTo", zh: "回到")
        case .minimized, .hiddenApp: return WSL10n.text("notch.verb.restore", zh: "还原")
        case .elsewhere: return WSL10n.text("notch.verb.goTo", zh: "去")
        case .parked: return WSL10n.text("notch.verb.slideIn", zh: "滑进来")
        case .session: return WSL10n.text("notch.action.goThere", zh: "过去")
        case .playing, .activity: return WSL10n.text("notch.action.open", zh: "打开")
        }
    }

    static func kindName(_ kind: NotchTile.Kind) -> String {
        switch kind {
        case .tucked: return WSL10n.text("silent.window.tuck", zh: "收进刘海")
        case .strip: return WSL10n.text("notch.where.strip", zh: "收起的窗口")
        case .thumbnail: return WSL10n.text("notch.where.thumbnail", zh: "收成缩略图的窗口")
        case .slideOver: return WSL10n.text("notch.where.slideOver", zh: "侧拉")
        case .carried: return WSL10n.text("menu.carryToAllDesktops", zh: "带到每张桌面")
        case .minimized: return WSL10n.text("notch.where.minimized", zh: "已最小化")
        case .hiddenApp: return WSL10n.text("notch.where.hiddenApp", zh: "已隐藏")
        case .elsewhere: return WSL10n.text("notch.where.elsewhere", zh: "在别的桌面")
        case .parked: return WSL10n.text("notch.where.parked", zh: "停在屏幕外的一列")
        case .session: return WSL10n.text("notch.kind.session", zh: "编程会话")
        case .playing: return WSL10n.text("say.preview.playing", zh: "正在播放")
        case .activity: return WSL10n.text("notch.where.activity", zh: "正在进行")
        }
    }

    private static func badge(_ kind: NotchTile.Kind) -> NSImage? {
        let name: String
        switch kind {
        case .tucked, .elsewhere, .session, .playing, .activity, .parked: return nil
        case .strip: name = "rectangle.topthird.inset.filled"
        // 缩略图格子的专属角标，和卷帘条的 rectangle.topthird 区分。
        case .thumbnail: name = "photo"
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

    /// 停 `Motion.Hold.tileDwell`（0.20 秒）才看：指针从一格划到另一格时不闪。
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        dwell?.invalidate()
        dwell = Timer.scheduledTimer(withTimeInterval: Motion.Hold.tileDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onHover?(true) }
        }
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        dwell?.invalidate()
        onHover?(false)
    }
    override func mouseDown(with event: NSEvent) {
        if let rect = accessoryRect, tile.ongoing?.accessory != nil,
           rect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) {
            onAccessory?()
            return
        }
        // 左段收着的一格：卷轴开着、接线开关开着时，按下先不算点一下，松手时没拖起来才算（SS-04）；其它时候照旧。
        if tile.kind == .tucked, Self.dragOut?.enabled(tile.id) == true {
            drag.press(tile.id, at: NSEvent.mouseLocation)
            return
        }
        let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
        onClick?(picture)
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag.isPressed, let hooks = Self.dragOut else { return }
        let point = NSEvent.mouseLocation
        switch drag.move(to: point) {
        case .none: return
        case .began:
            alphaValue = 0.5
            hooks.moved(tile.id, point)
        case .moved:
            hooks.moved(tile.id, point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag.isPressed else { return }
        alphaValue = 1
        switch drag.release(at: NSEvent.mouseLocation) {
        case .click:
            let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
            onClick?(picture)
        case .drop(let id, let point):
            Self.dragOut?.finished(id, point)
        case .none:
            break
        }
    }

    /// 拖着的时候这一格被收走（那一排收起、换桌面、锁屏）：这次拖动作废，窗口还在刘海里。
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, drag.cancel() else { return }
        let id = tile.id
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.dragOut?.finished(id, nil) } }
    }

    /// 右下角的小键（NP-4）：24 点的圆，离格子右边和下边各 10。只有带 accessory 的格子有。
    private var accessoryRect: NSRect? {
        guard tile.ongoing?.accessory != nil else { return nil }
        let side = CGFloat(NotchRow.OngoingCell.accessorySide)
        return NSRect(x: card.maxX - 10 - side, y: card.minY + 10, width: side, height: side)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var card: NSRect { NSRect(x: 0, y: 20, width: bounds.width, height: max(0, bounds.height - 20)) }

    private static func symbolImage(_ name: String, pointSize: CGFloat, color: NSColor,
                                    weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        return NotchActivitySymbol.image(name.isEmpty ? "circle.fill" : name)?.withSymbolConfiguration(configuration)
    }

    /// 竖线右边的格子：一个大符号、一行副句，右上角是这件事的状态——
    /// 会话在跑转圈（子图层）、等你是 8 点的橙点加“等你”、做完是对勾；音乐暂停时是暂停符号。
    /// 文件架这一格：最新的三张叠在一起（缩略图或类型图标），后面的往左上错开一点。
    private func drawFileShelfStack(in card: NSRect, count: Int) {
        let art = FileShelfCellArt.images(limit: min(3, count))
        guard !art.isEmpty else { return }
        let side: CGFloat = 52
        let center = NSPoint(x: card.midX, y: card.midY + 8)
        for (index, image) in art.enumerated().reversed() {
            let offset = CGFloat(index) * 7
            let rect = NSRect(x: center.x - side / 2 - offset + 7, y: center.y - side / 2 + offset - 7, width: side, height: side)
            let size = image.size
            guard size.width > 0, size.height > 0 else { continue }
            let scale = min(side / size.width, side / size.height)
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            let target = NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: target, xRadius: 12, yRadius: 12).addClip()
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: index == 0 ? 1 : 0.7)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(roundedRect: target.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// 量的完整说法放不下时，个数沿用右耳的短写；保字号与真实数，不把总数截成另一个数。
    static func quantityLabel(_ quantity: NotchActivity.Quantity, text: String, font: NSFont, availableWidth: CGFloat, color: NSColor? = nil) -> NSAttributedString {
        func label(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color ?? NSColor.white.withAlphaComponent(0.92),
            ])
        }
        let full = label(text)
        guard full.size().width > availableWidth, let short = quantity.shortCountText else { return full }
        return label(short)
    }

    private func drawOngoing(in card: NSRect) {
        guard let ongoing = tile.ongoing else { return }
        if let count = ongoing.shelfCount {
            drawFileShelfStack(in: card, count: count)
            return
        }
        if let image = Self.symbolImage(ongoing.symbol, pointSize: 30, color: NSColor.white.withAlphaComponent(0.92)) {
            let size = image.size
            image.draw(in: NSRect(x: card.midX - size.width / 2, y: card.midY - size.height / 2 + 8,
                                  width: size.width, height: size.height))
        }
        // 右下角留一个 24 点的播放 / 暂停键（音乐，NP-4）；副句让出它占的那一截，左对齐。
        let key = accessoryRect
        if !ongoing.subtitle.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = key == nil ? .center : .left
            paragraph.lineBreakMode = .byTruncatingTail
            let left = card.minX + (key == nil ? 8 : 12)
            let right = key.map { $0.minX - 6 } ?? card.maxX - 8
            NSAttributedString(string: ongoing.subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
                .paragraphStyle: paragraph,
            ]).draw(with: NSRect(x: left, y: card.minY + 8, width: max(0, right - left), height: 14),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if let key {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: key).fill()
            if let icon = Self.symbolImage(ongoing.isPaused ? "play.fill" : "pause.fill", pointSize: 11,
                                           color: NSColor.white.withAlphaComponent(0.92), weight: .semibold) {
                let size = icon.size
                icon.draw(in: NSRect(x: key.midX - size.width / 2, y: key.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        // 右上角的量：环（或弧，子图层）左边写数字；只有个数就只写字。和紧凑右耳同一套。
        var quantityLeft = card.maxX - 10
        switch ongoing.quantity.drawing {
        case .ring, .spinningArc: quantityLeft -= CGFloat(NotchProgressPart.ringDiameter) + CGFloat(NotchProgressPart.textGap)
        case .countText, .none: break
        }
        if let text = ongoing.quantityText, !text.isEmpty {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
            let available = max(0, quantityLeft - card.minX - 10)
            let label = Self.quantityLabel(ongoing.quantity, text: text, font: rounded, availableWidth: available, color: ongoing.phase == .quotaLow ? .systemOrange : nil)
            let size = label.size()
            let width = min(ceil(size.width), available)
            label.draw(with: NSRect(x: quantityLeft - width, y: card.maxY - 10 - 7 - size.height / 2, width: width, height: size.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            quantityLeft -= width + CGFloat(NotchProgressPart.textGap)
        }
        switch ongoing.phase {
        case .waiting?:
            let diameter = CGFloat(NotchInfoDot.diameter)
            let dot = NSRect(x: card.maxX - 10 - diameter, y: card.maxY - 10 - diameter, width: diameter, height: diameter)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
            let label = NSAttributedString(string: WSL10n.text("notch.session.waitingTag", zh: "等你"), attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.systemOrange,
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: dot.minX - 4 - size.width, y: dot.midY - size.height / 2))
        case .done?:
            Self.symbolImage("checkmark.circle.fill", pointSize: 14, color: .systemGreen, weight: .semibold)?
                .draw(in: NSRect(x: card.maxX - 10 - 14, y: card.maxY - 10 - 14, width: 14, height: 14))
        case .running?, .quota?, .quotaLow?, nil:
            if ongoing.phase == nil, ongoing.isPaused {
                // 暂停符号在量（环、数字）的左边，不叠在上面。
                let drawsQuantity = ongoing.quantity.drawing != .none
                Self.symbolImage("pause.fill", pointSize: 11, color: NSColor.white.withAlphaComponent(0.7), weight: .semibold)?
                    .draw(in: NSRect(x: (drawsQuantity ? quantityLeft : card.maxX - 10) - 12, y: card.maxY - 10 - 12, width: 12, height: 12))
            }
        }
    }

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
        if tile.kind.isOngoing {
            drawOngoing(in: card)
        } else if let snapshot = tile.snapshot, let rect = pictureRect {
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
        if keyboardFocused {
            let width = CGFloat(NotchFocusController.Style.stroke(increasedContrast: SystemAppearanceCapabilities.current.increaseContrast))
            NSColor.white.setStroke()
            let ring = NSBezierPath(roundedRect: card.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: 14 - width / 2, yRadius: 14 - width / 2)
            ring.lineWidth = width
            ring.stroke()
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
        } else if let ongoing = tile.ongoing,
                  let image = Self.symbolImage(ongoing.symbol, pointSize: 11, color: NSColor.white.withAlphaComponent(0.8)) {
            image.draw(in: NSRect(x: 1, y: 3, width: 14, height: 14))
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
        let label = NSTextField(labelWithString: WSL10n.text("glance.stalePicture", zh: "收起时的画面"))
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
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // 动画完成回调在主线程。
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}
