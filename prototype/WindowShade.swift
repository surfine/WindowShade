// WindowShade 主文件：全局常量与 AppDelegate 骨架（启动、观察者、生命周期）。
//
// 功能按目录拆分，文件级基础设施也各有归属：
//   App/        折叠入口、事务、出口、事件 tap、菜单、偏好、悬停预览、权限
//   Capture/    截图缓存、图像分析、SCShareableContent 缓存
//   Compatibility/  各 app 窗口策略与按应用的判断
//   Core/       折叠状态机与折叠相关的值类型
//   Overlay/    覆盖层窗口与视图
//   Private/    SkyLight 私有 API 隔离层
//   Recovery/   恢复日志与离屏救援
//   Support/    日志、主线程活动标记与卡顿哨兵
//   Window/     AX 辅助、窗口列表、外框画像、坐标换算
//
// 编译与运行见 prototype/build.sh（自动收集源文件，签名身份走环境变量）。

import Cocoa
import os
import Carbon.HIToolbox
import ApplicationServices
import ScreenCaptureKit
import QuartzCore
import CoreText
import Darwin
import ServiceManagement

let titleBarHeight: CGFloat = 28
let classicTitleBarHeight: CGFloat = 24
let proxyTitleBarHeight: CGFloat = 34
let quickLookOriginalTitleBarHeight: CGFloat = 38
let standardTitleBarMaxCropHeight: CGFloat = 64
let adobeApplicationFrameChromeHeight: CGFloat = 112
let adobeTabbedDocumentChromeHeight: CGFloat = 84
let adobeFloatingDocumentChromeHeight: CGFloat = 44
// 实测裁切（2026-07，本机截图对照）：通用 112pt 会切进面板内容。
// AE = 细标题栏 + 工具条两排，止于 Project/Effect Controls 面板标签行之前。
// Premiere = 一体化单条标题栏（交通灯与 Import/Edit/Export 同排），
// 其下的面包屑/侧栏是内容。
let afterEffectsWorkspaceChromeHeight: CGFloat = 56
let premiereWorkspaceChromeHeight: CGFloat = 40
let shadeAppearanceModeDefaultsKey = "ShadeAppearanceMode"
let shadeFloatingOnTopDefaultsKey = "ShadeFloatingOnTop"
let shadeTranslucentDefaultsKey = "ShadeTranslucent"
let shadeTitlebarDoubleClickDefaultsKey = "ShadeTitlebarDoubleClickEnabled"
let shadeSoundEnabledDefaultsKey = "ShadeSoundEnabled"
let shadeFoldSoundDefaultsKey = "ShadeFoldSound"
let shadeUnfoldSoundDefaultsKey = "ShadeUnfoldSound"
let shadeSoundMigrationVersionDefaultsKey = "ShadeSoundMigrationVersion"
let shadeOnboardingShownDefaultsKey = "ShadeOnboardingShown"
let dockMineffectSessionActiveDefaultsKey = "DockMineffectSessionActive"
let dockMineffectHadOriginalDefaultsKey = "DockMineffectHadOriginal"
let dockMineffectOriginalDefaultsKey = "DockMineffectOriginal"
let shadeJournalDefaultsKey = "ShadeJournalEntries"
let shadeDebugWindowDumpDefaultsKey = "ShadeDebugWindowDump"
let shadeJournalMaxAge: TimeInterval = 14 * 24 * 60 * 60
let shadedWindowReconcileInterval: TimeInterval = 5
let journalRescueRetryInterval: TimeInterval = 30
let forwardedTrafficRetryDelays: [TimeInterval] = [0.035, 0.08, 0.14, 0.24, 0.40, 0.65]
let shadeTranslucentAlpha: CGFloat = 0.82
let axFullScreenAttribute = "AXFullScreen"
// AX 子树遍历预算：限制「顶部控件扫描」（collectTopChromeControlSamples）和
// firstToolbar 在最坏情况下的同步 IPC 数量。复杂窗口（浏览器等）的 AX 树可达
// 数千节点，无界遍历会让折叠/双击判定在忙 app 上长时间卡住主线程。
let axTraversalNodeBudget = 150
let axTraversalMaxChildrenPerNode = 40
let hoverPreviewMaxPixelSize = CGSize(width: 720, height: 480)
let menuHoverPreviewMaxSize = NSSize(width: 240, height: 160)
let shadeCaptureTimeoutNanoseconds: UInt64 = 450_000_000
let shadeDefaultFoldSound = "Purr"
let shadeDefaultUnfoldSound = "Pop"
/// 系统提示音的候选（第33批：显示名走目录，name 是系统音的名字、不翻译）。
var shadeSoundChoices: [(label: String, name: String)] {
    [(WSL10n.text("sound.purr", zh: "柔和（Purr）"), "Purr"),
     (WSL10n.text("sound.submarine", zh: "低调（Submarine）"), "Submarine"),
     (WSL10n.text("sound.blow", zh: "轻吹（Blow）"), "Blow"),
     (WSL10n.text("sound.tink", zh: "细微轻响（Tink）"), "Tink"),
     (WSL10n.text("sound.glass", zh: "玻璃（Glass）"), "Glass"),
     (WSL10n.text("sound.pop", zh: "弹开（Pop）"), "Pop")]
}
/// main.swift 启动时在主线程写一次，之后只读。
nonisolated(unsafe) var appDelegate: AppDelegate?

func framesAlmostEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {
    abs(a.minX - b.minX) <= tolerance &&
    abs(a.minY - b.minY) <= tolerance &&
    abs(a.width - b.width) <= tolerance &&
    abs(a.height - b.height) <= tolerance
}

func cgWindowID(for window: NSWindow) -> CGWindowID? {
    let number = window.windowNumber
    guard number > 0, number <= Int(UInt32.max) else { return nil }
    return CGWindowID(UInt32(number))
}

// MARK: - App 主体

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let duoController = DuoController()
    final class PendingTitlebarTripleClick {
        let id: CGWindowID
        let point: CGPoint
        var deadline: Date
        let intent = TitlebarTripleClickIntent()
        var foldTransactionID: UUID?

        init(id: CGWindowID, point: CGPoint, deadline: Date) {
            self.id = id
            self.point = point
            self.deadline = deadline
        }
    }

    struct PendingSpaceReturn {
        let displayID: CGDirectDisplayID
        let sourceSpaceID: UInt64
        let deadline: Date
    }

    // reconcile 需要知道真实窗口是否仍存在/最小化，但这些 AX 读取可能被忙 app
    // 阻塞数秒。每个 app 最多一个在途读取，全局同时最多 4 个；主线程只应用已经返回的结果。
    struct ReconcileAXTarget {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let needsMinimizedState: Bool
        let stamp: WS2FoldCallbackStamp
    }

    struct ReconcileAXSnapshot: Sendable {
        let stamp: WS2FoldCallbackStamp
        var id: CGWindowID { stamp.window }
        let position: CGPoint?
        let size: CGSize?
        let isMinimized: Bool?
    }

    // 救援扫描产出的待写回动作：扫描（AX 读取）在后台，写回在主线程。

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    /// 注册失败（被其他应用占用）的快捷键编号；菜单不再显示这些组合。
    var unavailableHotKeyIDs: Set<UInt32> = []
    var shaded: [CGWindowID: ShadeState] = [:]
    var overlayIDs: Set<CGWindowID> = []      // 我们自己的覆盖层，tap 里要跳过它们
    var arrangedOverlayFrames: [CGWindowID: NSRect] = [:]
    var focusSideStackFrames: [CGWindowID: NSRect] = [:]
    var focusPulledOutOverlayIDs: Set<CGWindowID> = []
    var focusPulledOutRestoreFrames: [CGWindowID: NSRect] = [:]
    var focusPulledOutOriginalSizes: [CGWindowID: CGSize] = [:]
    var focusRejoinStackFrames: [CGWindowID: NSRect] = [:]
    var focusRejoinEntries: [CGWindowID: FocusSessionEntry] = [:]
    var focusSession: FocusSession?
    // 分帧折叠进行中：期间不接受新的专注请求，避免两次级联交叉污染会话状态。
    var focusCascadeActive = false
    var accessibilityActionTargets: [CGWindowID: ShadedAccessibilityActionTarget] = [:]   // FoldExit/ShadeStrip 扩展跨文件访问
    var isProgrammaticOverlayArrangement = false
    private var scaleMinimizeActive = false           // 临时把最小化动画改成 scale（退出还原用户原设置）
    private var originalDockMinimizeEffect: String?   // nil = 原本没有设置 mineffect
    private var dockMinimizeEffectChanged = false
    // Dock 会话逻辑的后台串行队列：defaults 读写和 killall Dock 都是子进程同步
    // 调用，不该占用主线程（启动/菜单切换都走这里）。实例状态在后台算好、回主
    // 线程应用；退出用 dockWorkQueue.sync 兜底，按持久化的 session 键恢复，
    // 天然抗「启用/恢复」在途操作交错。
    private let dockWorkQueue = DispatchQueue(label: "WindowShade.dock", qos: .utility)
    nonisolated(unsafe) var dockToolRunnerOverride: DockToolRunner?   // 仅测试注入
    private var dockOperationInFlight = false         // 主线程专用：防重复入队启用
    // 截图像素分析（chrome 高度扫描、健康检查、圆角镜像）用的后台队列：纯 CPU
    // 计算（4K Retina 全宽可达数 MB 缓冲），挪出主线程避免折叠瞬间卡 UI。
    let pixelAnalysisQueue = DispatchQueue(label: "WindowShade.pixels", qos: .userInitiated)
    // 救援扫描的后台队列：journal 逐 app AX 枚举和广域兜底扫描可能被忙 app 拖住
    // 数秒，必须离开主线程。窗口位置写回统一在主线程执行，写回前复查 shaded
    // 是否为空，避免与正在进行的折叠操作交错。
    let rescueWorkQueue = DispatchQueue(label: "WindowShade.rescue", qos: .utility)
    var isRescuingOffscreenWindows = false
    var isRescueQueued = false
    private var tapSetupTimer: Timer?
    // 装好之后的周期体检，见 startEnvironmentWatch()：
    private var environmentWatch: Timer?
    private var tapSilentStops = 0
    private var lastAccessibilityTrusted = true
    // 睡醒后的三档恢复（规格 R3），见 startWakeRecovery()。
    private var wakeRecoveryObservers: [NSObjectProtocol] = []
    private var wakeRecoveryWork: [DispatchWorkItem] = []
    /// 收起的区间标记（规格 N3）：按窗口号存，在 settleFoldWaiters 里结束。
    var foldSignposts: [CGWindowID: OSSignpostIntervalState] = [:]
    var reconcileTimer: Timer?
    var isReconcilingShadedWindows = false
    var axReadGate = AXReadGate<pid_t, [WS2FoldCallbackStamp]>()
    var reconcileInvalidCounts: [CGWindowID: Int] = [:]
    var privateAlphaOriginalValues: [CGWindowID: Float] = [:]
    // 本机的跨进程 SkyLight alpha 写入是否已被确认无效（SIP 限制）。
    var privateAlphaKnownIneffective = false
    var duoRestoreVerificationTokens: [CGWindowID: UUID] = [:]
    var restoreFocusTokens: [CGWindowID: UUID] = [:]
    var recoveryJournalOverride: DurableShadeJournal?
    var lastJournalRescueAttempt: Date?
    var focusParkingWindow: NSWindow?
    // 当前唯一在屏幕上的预览视窗（菜单悬停或标题栏 peek 触发），见 presentPreview/
    // hidePreview。同一时刻只可能有一个，这是结构性不变量，不是巧合。
    var activePreview: ActivePreview?
    /// 浅深色切换的 KVO 令牌（系统外观刷新用）。
    var appearanceObservation: NSKeyValueObservation?
    // 标题栏单击 peek 的「意图」追踪：跨异步懒截图等待期，防止用户已经移开后
    // 慢截图才回来还硬生生弹出一个不相干窗口的预览。
    var peekHoverID: CGWindowID?
    var pendingSpaceReturns: [CGWindowID: PendingSpaceReturn] = [:]
    // 菜单悬停的「意图」追踪：同上，键于 highlight 变化而非 overlay 位置。
    var menuPreviewHoverID: CGWindowID?
    var menuPreviewAnchor: NSRect?
    var shadeOperationIDs: Set<CGWindowID> = []
    // 显式窗口状态机：operationStates[id] 缺失即 .normal。
    // capturing/failed 为操作期瞬态，folded/restoring 为会话期状态。
    private var operationStates: [CGWindowID: WindowShadeState] = [:]
    var previewCapturePendingIDs: Set<CGWindowID> = []
    var hoverPreviewSuppressedUntil: [CGWindowID: Date] = [:]
    var statusNoticeWorkItem: DispatchWorkItem?
    var onboardingWindow: NSWindow?
    // 窗口浏览入口的折叠终态等待者：键 = 原窗口 ID，值 = token -> 回调。
    // 折叠事务是异步的（立即验证 / 延迟验证 / 回滚），浏览器动作只在真实终态
    // 到达时才完成；token 保证旧请求不会误结算新请求。
    var foldWaiters: [CGWindowID: [UUID: (Bool) -> Void]] = [:]
    var foldWaiterTransactions: [UUID: UUID] = [:]
    var foldObserverSerial: UInt = 0
    var foldObserverRoutes: [UInt: WS2FoldObserverRoute] = [:]
    var foldPresentationID = UUID()
    var foldEvidence = WS2FoldEvidence()
    var foldEvidenceMayCommit: [UUID: () -> Bool] = [:]
    var foldEvidenceCallbacks: [UUID: (WS2FoldEvidence.Event) -> Void] = [:]
    var windowBrowserController: WindowBrowserController?
    var windowBrowserHotKeyRef: EventHotKeyRef?
    var menuRebuildWorkItem: DispatchWorkItem?
    var suppressMenuRebuilds = false
    var pendingMenuRebuild = false
    var isUpdatingMenuFromDelegate = false
    private var pinnedPreviewFocusMonitor: Any?
    private var pinnedPreviewTargetRefreshWorkItem: DispatchWorkItem?
    private var titlebarPrefetchInFlight = false
    private var titlebarPrefetchGeneration: UInt64 = 0
    var spaceRefreshWorkItem: DispatchWorkItem?
    /// 上一次看到的显示器与各屏可用区域，用来分辨"真的换了屏"和"只是菜单栏、Dock 变了"。
    var lastDisplayLayout = DisplayLayout(screens: [])
    var lastVisibleFrames: [CGRect] = []
    weak var onboardingPermissionStack: NSStackView?
    weak var onboardingProgressLabel: NSTextField?
    weak var onboardingDoneButton: NSButton?
    weak var onboardingCaption: NSTextField?
    var onboardingRefreshTimer: Timer?
    let onboardingContentWidth: CGFloat = 452
    var suppressUnshadeSounds = false
    var ownsGlobalInput = true
    var pendingTitlebarTripleClick: PendingTitlebarTripleClick?
    var restorePinTokens: [CGWindowID: UUID] = [:]
    var titlebarEventTapBypassUntil: Date?
    var soundEnabled: Bool = {
        ShadeSoundPreference.isEnabled(in: .standard, key: shadeSoundEnabledDefaultsKey)
    }()
    var foldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeFoldSoundDefaultsKey) ?? shadeDefaultFoldSound
    }()
    var unfoldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeUnfoldSoundDefaultsKey) ?? shadeDefaultUnfoldSound
    }()
    var appearanceMode: ShadeAppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: shadeAppearanceModeDefaultsKey) ?? ""
        let mode = ShadeAppearanceMode(rawValue: raw) ?? .nativeScreenshot
        return mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
    }()
    var titlebarDoubleClickEnabled: Bool = {
        if UserDefaults.standard.object(forKey: shadeTitlebarDoubleClickDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeTitlebarDoubleClickDefaultsKey)
    }()
    var floatingOnTop: Bool = {
        if UserDefaults.standard.object(forKey: shadeFloatingOnTopDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeFloatingOnTopDefaultsKey)
    }()
    var translucent: Bool = UserDefaults.standard.bool(forKey: shadeTranslucentDefaultsKey)
    var eventTap: CFMachPort?                          // 供 C 回调重新启用
    var eventTapReenableWorkItem: DispatchWorkItem?
    let offscreen = CGPoint(x: -32000, y: -32000)
    let defaultShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: nil,
                                                             capturePreview: true,
                                                             emitFoldFeedback: true,
                                                             rebuildMenuAfterInstall: true)
    let focusShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: .proxyTitleBar,
                                                           capturePreview: false,
                                                           emitFoldFeedback: false,
                                                           rebuildMenuAfterInstall: false)
    /// 看一眼：指针停在卷帘条上，窗口原样出现，移开就收回。
    lazy var glance = MainActor.assumeIsolated { GlanceController(owner: self) }
    /// 静音「方便遮一下」：逐屏不透明遮罩，观察可见才回报完成。
    lazy var silentPrivacyCover = MainActor.assumeIsolated { WS2SilentPrivacyCoverController() }
    /// 带到每张桌面：窗口留在自己的桌面，别的桌面上看得到它的卷帘条。
    lazy var carry = MainActor.assumeIsolated { CarryController(owner: self) }
    lazy var slideOver = MainActor.assumeIsolated { SlideOverController(owner: self) }
    lazy var notch = MainActor.assumeIsolated { NotchController(owner: self) }
    lazy var ws2Runtime = MainActor.assumeIsolated { WS2AppRuntime(owner: self) }
    /// 妙控外设连上、电量低时在刘海上说一句（App/DeviceBatteryController.swift）。
    lazy var deviceBattery = MainActor.assumeIsolated { DeviceBatteryController() }
    lazy var launchpad = MainActor.assumeIsolated { LaunchpadController(owner: self) }
    lazy var gestures = MainActor.assumeIsolated { TrackpadGestureController(owner: self) }
    /// 再点一下 Dock 图标让开这个 App（见 DockClickHide.swift）。
    lazy var dockClick = MainActor.assumeIsolated { DockClickHide() }
    /// 按住 ⌥（或 ⌘）连按 Tab 按窗口切换（见 WindowSwitcher.swift）。
    lazy var switcher = MainActor.assumeIsolated { WindowSwitcher(owner: self) }
    /// Dock 留在一块屏上（见 DockLock.swift）。
    lazy var dockLock = MainActor.assumeIsolated { DockLock() }
    /// 分屏：两扇拼满一块屏时中间的把手（见 SplitView.swift）。
    lazy var splitView = MainActor.assumeIsolated { SplitViewController(owner: self) }
    /// 画中画：任意窗口缩成实时画面浮在角落（见 PictureInPicture.swift）。
    lazy var pip = MainActor.assumeIsolated { PictureInPictureController(owner: self) }
    /// 调度中心里按 ⌘W 关窗、⌘Q 退出 App（见 MissionControlKeys.swift）。
    lazy var missionControlKeys = MissionControlKeys()
    let inputController = WS2InputController()
    lazy var pinnedPreviewController = PinnedPreviewController(
        notice: { [weak self] message, log in
            self?.quietNotice(message, log: log)
        },
        sessionsDidChange: { [weak self] in
            self?.scheduleMenuRebuild()
        }
    )
    /// 静音路径收起异步完成（R03）：FoldCompletion 回执，供宿主读取。
    private(set) var lastSilentFoldCompletion: (id: CGWindowID, ok: Bool, at: CFTimeInterval)?

    func noteSilentFoldCompletion(id: CGWindowID, ok: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        lastSilentFoldCompletion = (id, ok, CACurrentMediaTime())
        wlog("shade: silent fold completion id=\(id) ok=\(ok)")
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // 启动时发现要换回旧版、看护又不在：进程内换回在后台跑，这期间先不接管任何东西（事件钩子、收起……）。
        // 换回成功进程直接退出；没成就在主线程上补跑下面整段启动（见 App/UpdaterLaunch.swift）。
        if UpdateLaunch.deferLaunchIfRestoring({ [weak self] in self?.applicationDidFinishLaunching(note) }) { return }
        // 新装还是升级：赶在这一次启动写下任何设置之前认一次、存下来（声音迁移每次启动都写，清理收起记录会删键；
        // 见 App/GlobalShortcuts.swift 的 InstallHistory）。
        _ = InstallHistory.settled(in: .standard)
        // 量耗电等场合另开一份：刘海不播报、不教，也不把"教过"写进设置。
        if CommandLine.arguments.contains("--no-teach") { NotchController.probeSilence = true }
        // 代理应用也要有标准主菜单：文本编辑快捷键与 ⌘W 都靠它的 key equivalent 派发。
        installStandardMainMenu()
        duoController.start(owner: self)
        let sessionFormatter = DateFormatter()
        sessionFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sessionFormatter.locale = Locale(identifier: "en_US_POSIX")
        wlog("=== session start pid=\(getpid()) at \(sessionFormatter.string(from: Date())) ===")
        // 防 App Nap：本进程持有全局 CGEventTap（回调在主 RunLoop 执行），
        // 被 nap 后每次双击都会拖慢全系统鼠标事件直到 tap 被系统超时禁用；
        // 计时器（reconcile/watchdog/菜单刷新）也会被合并推迟数十秒。
        // 只留这一条最小声明，不带 `.latencyCritical`——「计时器不被合并」是交互期间才要的
        // 待遇（见 AppNapActivity：关键输入路径按作用域拿租约），不是进程一辈子的声明。
        appNapActivity.holdBase()
        MainThreadStallSentinel.shared.start()
        // 启动序列逐步计时：任何一步超过 100ms 都会记录，用于定位启动期主线程阻塞。
        logIfSlow("launch migrateSounds", threshold: 0.1) { migrateDistractingDefaultSounds() }
        logIfSlow("launch pruneJournal", threshold: 0.1) { pruneShadeJournal(reason: "launch") }
        logIfSlow("launch statusItem", threshold: 0.1) { setupStatusItem() }
        logIfSlow("launch dockEffect", threshold: 0.1) { enableScaleMinimizeEffectForSession() }
        logIfSlow("launch hotKey", threshold: 0.1) { registerHotKey() }
        logIfSlow("launch ensureAX", threshold: 0.1) { _ = ensureAccessibility() }
        // 把本进程所有同步 AX 调用的超时从系统默认 6s 收紧到 2s。
        // 目标 app 无响应时，event tap 回调和主线程最多被拖 2s 而不是 6s；
        // 正常 app 的 AX 属性读取都在毫秒级，不受影响。
        logIfSlow("launch axTimeout", threshold: 0.1) {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
        }
        logIfSlow("launch onboarding", threshold: 0.1) { showPermissionOnboardingIfNeeded(force: false) }
        logIfSlow("launch eventTap", threshold: 0.1) { setupEventTapWhenTrusted() }
        startWakeRecovery()
        SystemLog.lifecycle.notice("launch version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?", privacy: .public) build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?", privacy: .public) accessibility=\(AXIsProcessTrusted(), privacy: .public)")
        logIfSlow("launch gestures", threshold: 0.1) {
            MainActor.assumeIsolated { gestures.refreshMonitors() }
        }
        MainActor.assumeIsolated { installStripKeyForwarding() }
        // 刷脸实验：默认关（FaceScan.experiment.enabled），关着时什么都不建。只产证据，不解锁。
        MainActor.assumeIsolated { FaceScanExperiment.startIfEnabled() }
        MainActor.assumeIsolated {
            // 那一排里焦点落在会话格还是窗口格：告诉遥控器（M09）。遥控模式没开时没有宿主，什么都不会发生。
            notch.onShelfFocusKind = { [weak self] kind in self?.inputController.remoteHostForSettings?.layerEffects?.focusChanged(kind) }
            SlideOverRecovery.recoverAbandoned(); notch.install()
        }
        // 番茄钟的唯一宿主：在这里点一次，让观察者和唯一 FocusTimerHost 建起来。
        MainActor.assumeIsolated { _ = ws2Runtime }
        // 卡住时刘海开口：跟着来处、刘海和教学的开关装上或拆掉只听的钩子（见 App/HabitContext.swift）。
        MainActor.assumeIsolated { HabitCenter.shared.start(owner: self) }
        // 预热推迟到启动后 4 秒，不和启动抢资源；第一次打开前通常早已完成，没完成时 show() 自己会解码。
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated { self?.launchpad.warmUp() }
        }
        MainActor.assumeIsolated {
            dockClick.onHidden = { [weak self] app in
                guard let self else { return }
                if !self.notch.teach(.dockHide) {
                    self.notch.announce(WSL10n.text("dock.stepAside", zh: "已让开 %@", app.localizedName ?? WSL10n.text("dock.stepAside.it", zh: "它")),
                                detail: WSL10n.text("gesture.coach.dockHideHint", zh: "再点一下 Dock 图标就回来"), tone: .done)
                }
            }
            dockClick.start(); switcher.applySetting(); dockLock.apply(); splitView.start()
            missionControlKeys.applySetting()
        }
        logIfSlow("launch input", threshold: 0.1) { inputController.apply() }
        ArrangeGap.points = CGFloat(UserDefaults.standard.double(forKey: ArrangeGap.defaultsKey))
        logIfSlow("launch pinTracking", threshold: 0.1) { setupPinnedPreviewFocusTracking() }
        logIfSlow("launch windowBrowser", threshold: 0.1) {
            let browser = WindowBrowserController(owner: self)
            windowBrowserController = browser
            browser.start()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(appTerminated(_:)),
                                                          name: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(frontmostApplicationChanged(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(activeSpaceChanged(_:)),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)
        lastDisplayLayout = .current()
        lastVisibleFrames = NSScreen.screens.map(\.visibleFrame)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenParametersChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        // 系统外观开关（减少透明度 / 提高对比度 / 减少动态效果）变化时，
        // 已打开的卷帘条、悬停缩略图、置顶预览与窗口浏览面板立即跟着刷新。
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemAppearanceOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil)
        // 强调色与系统颜色变化：刷新自定义表面里用到的语义颜色。
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemAppearanceOptionsChanged(_:)),
            name: NSColor.systemColorsDidChangeNotification, object: nil)
        // 界面语言切换（第27批）：状态菜单立刻按新语言重建；设置窗口自己观察同一通知重建整窗。
        // 已显示的刘海句子不回溯改写，下一句起就是新语言（证据里如实记录）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(interfaceLanguageChanged(_:)),
            name: InterfaceLanguagePreference.didChangeNotification, object: nil)
        // 浅深色切换没有公开的 NSApplication 通知：用 KVO 观察 effectiveAppearance，
        // 变化时同样只刷新材质与边线。
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            // AppKit 在修改这个属性的线程上回调；effectiveAppearance 只在主线程改。
            MainActor.assumeIsolated {
                self?.systemAppearanceOptionsChanged(
                    Notification(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification))
            }
        }
        // 应用内更新（App/Updater.swift）：最后启动；装好新版本后两项授权没了，翻到欢迎窗口的授权页请他再打开一次。
        MainActor.assumeIsolated {
            UpdaterController.shared.onPermissionsLostAfterUpdate = { [weak self] in self?.showPermissionsAgainAfterUpdate() }
            UpdaterController.shared.confirmChange = { [weak self] target, done in
                guard let authentication = self?.notch.authentication, authentication.canAuthorize else { return false }
                authentication.authorize(target, completion: done)
                return true
            }
            UpdaterController.shared.start()
            deviceBattery.announce = { [weak self] key, text, detail, symbol, priority, ttl, ear, redEar, redIcon in
                self?.notch.announceWhenFree(key: key, text: text, detail: detail, symbol: symbol, priority: priority, ttl: ttl,
                                             ear: ear, speaks: true, redEar: redEar, redIcon: redIcon)
            }
            deviceBattery.onPowerFlash = { [weak self] flash in self?.notch.showPowerFlash(flash) }
            deviceBattery.isNotchBusy = { [weak self] in self?.notch.isBusyForPowerFlash ?? true }
            deviceBattery.onLow = { [weak self] id, name, part, percent in
                self?.notch.away.noteLowBattery(deviceID: id, name: name, part: part, percent: percent)
            }
            notch.away.deviceIsCurrent = { [weak self] id, part in self?.deviceBattery.isStillLow(deviceID: id, part: part) ?? false }
            deviceBattery.start()
            // 相机列表在后台枚举（菜单"检测面部动作"读缓存，主线程不再卡几百毫秒）。
            MainActor.assumeIsolated { FaceObservationSource.startWatchingCameras() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) { MainActor.assumeIsolated { _ = WS2URLHandler.shared.open(urls) } } // windowshade://lock（App/WS2URLHandler.swift）

    /// 更新下载、解包、把关的途中退出：先否决、确认 Sparkle 停了再放行（App/Updater.swift）；平时直接退出。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 第七份：正常退出由运行时统一把关（更新器 + owned 助手；先收票据与界面，再放行）。
        MainActor.assumeIsolated { ws2Runtime.applicationShouldTerminate() }
    }

    /// 界面语言切换（第27批）：重建状态菜单（文案按新语言）；设置窗口由自己的观察者重建整窗。
    /// 已显示的刘海句子不回溯改写。放到本次事件之后再重建，避免在语言行的 action 里同步拆视图。
    @objc func interfaceLanguageChanged(_ note: Notification) {
        dispatchPrecondition(condition: .onQueue(.main))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainThreadActivity.push("menu: 语言切换重建")
            defer { MainThreadActivity.pop() }
            self.rebuildMenu()
        }
    }

    /// 辅助功能外观变化：只刷新材质/边线/阴影，不动窗口状态、不触发任何捕获。
    @objc func systemAppearanceOptionsChanged(_ note: Notification) {
        dispatchPrecondition(condition: .onQueue(.main))
        // 同上：外观开关的通知回调也要能在卡顿归因里看出名字。
        MainThreadActivity.push("system: 外观开关变化")
        defer { MainThreadActivity.pop() }
        let capabilities = SystemAppearanceCapabilities.current
        wlog("appearance: system options changed reduceTransparency="
             + "\(capabilities.reduceTransparency) increaseContrast=\(capabilities.increaseContrast) "
             + "reduceMotion=\(capabilities.reduceMotion)")
        // 卷帘条：经典条按当前开关重绘，截图条只需刷新可访问性/边线。
        for state in shaded.values {
            guard let content = state.overlay?.contentView else { continue }
            content.needsDisplay = true
            (content as? TitleStripView)?.applySystemAppearance(capabilities: capabilities)
            (content as? ClassicTitleStripView)?.appearanceCapabilities = capabilities
            // 经典条的颜色由应用图标色调 × 当前外观推出：外观变化后必须重算。
            (content as? ClassicTitleStripView)?.refreshPalette()
        }
        // 置顶预览会话与临时悬停缩略图。
        pinnedPreviewController.refreshSystemAppearance(capabilities: capabilities)
        // 刘海岛的边线跟着"提高对比度"走（设计系统 §6-11）：按当前状态重画一次。
        MainActor.assumeIsolated { notch.refreshAppearance() }
        (activePreview?.window.contentView as? SafariStylePreviewView)?
            .applySystemAppearance(capabilities: capabilities)
        (activePreview?.window.contentView as? PinnedLivePreviewView)?
            .applySystemAppearance(capabilities: capabilities)
        windowBrowserController?.refreshSystemAppearance()
    }

    /// 安装标准最小主菜单（关于/设置/服务/隐藏/退出 + 编辑 + 窗口）。
    /// 代理应用不显示菜单栏，但文本框与关闭快捷键按系统习惯工作。
    func installStandardMainMenu() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "WindowShade"
        NSApp.mainMenu = StandardMenu.make(appName: appName,
                                           settingsTarget: self,
                                           settingsAction: #selector(showPreferences),
                                           aboutTarget: self,
                                           aboutAction: #selector(showAboutPanel))
    }

    private func migrateDistractingDefaultSounds() {
        let defaults = UserDefaults.standard
        let migrationVersion = defaults.integer(forKey: shadeSoundMigrationVersionDefaultsKey)
        // 规格 R5：真要迁移时先把整个设置域原样留一份（Application Support/WindowShade/backup/）。
        if migrationVersion < 2 { SettingsArchiveIO.backupBeforeMigration(label: "sound-v2") }
        let retiredFoldSounds = ["Tink", "WindowShadeSoftFold"]
        if let foldSound = defaults.string(forKey: shadeFoldSoundDefaultsKey),
           retiredFoldSounds.contains(foldSound) {
            defaults.set(shadeDefaultFoldSound, forKey: shadeFoldSoundDefaultsKey)
            foldSoundName = shadeDefaultFoldSound
        }
        let retiredUnfoldSounds = ["Bottle", "WindowShadeSoftUnfold"]
        if let unfoldSound = defaults.string(forKey: shadeUnfoldSoundDefaultsKey),
           retiredUnfoldSounds.contains(unfoldSound) {
            defaults.set(shadeDefaultUnfoldSound, forKey: shadeUnfoldSoundDefaultsKey)
            unfoldSoundName = shadeDefaultUnfoldSound
        } else if migrationVersion < 2,
                  defaults.string(forKey: shadeUnfoldSoundDefaultsKey) == "Purr" {
            defaults.set(shadeDefaultUnfoldSound, forKey: shadeUnfoldSoundDefaultsKey)
            unfoldSoundName = shadeDefaultUnfoldSound
        }
        defaults.set(2, forKey: shadeSoundMigrationVersionDefaultsKey)
    }






    // 目标解析是后台单飞 AX 工作；只有实际 target 改变才重建菜单。这样一次点击
    // 不会再形成"刷新 → rebuild → 再刷新"的同步 AX 放大链路。
    func refreshPinnedPreviewTarget(reason: String) {
        pinnedPreviewController.refreshCurrentTarget(reason: reason) { [weak self] _, didChange in
            guard didChange else { return }
            self?.scheduleMenuRebuild()
        }
    }

    private func setupPinnedPreviewFocusTracking() {
        refreshPinnedPreviewTarget(reason: "launch")
        pinnedPreviewFocusMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // NSEvent 全局 monitor 仍在主线程回调；连 WindowServer 的标题栏预过滤
            // 也可能很慢。预热整体放到后台，连续点击至多留一份工作，过时结果直接丢弃。
            if #available(macOS 14.0, *), event.type == .leftMouseDown {
                self?.scheduleTitlebarPrefetch(clickState: event.clickCount)
            }
            self?.schedulePinnedPreviewTargetRefresh()
        }
    }

    @available(macOS 14.0, *)
    private func scheduleTitlebarPrefetch(clickState: Int) {
        // 只在第一下点击时做：第二下落地时内容已就绪，或本来就会强制刷新。
        guard clickState == 1 else { return }
        titlebarPrefetchGeneration &+= 1
        guard titlebarDoubleClickEnabled, !titlebarPrefetchInFlight else { return }
        let wantsPrefetch = TitlebarPrefetchGate.shouldPrefetch(
            clickState: clickState,
            animationEnabled: DuoSettings.load().windowsEnabled,
            fastCaptureDisabled: FastCapture.isDisabledByEnvironment)
        let profileHeights = ChromeProfileCache.shared.freshHitBarHeights()
        titlebarPrefetchInFlight = true
        let generation = titlebarPrefetchGeneration
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: coordinateBaselineY() - mouse.y)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // 第一下点击刷新窗口列表时顺手记下准入快照，给 tap 线程上的第二下用。
            let windows = WindowListCache.shared.onScreenWindows()
            WindowListCache.shared.recordAdmissionSnapshot(windows)
            let mayBeTitlebar = wantsPrefetch && pointMayLieInTitlebarBand(point, windows: windows) { id in
                TitlebarPrefetchGate.bandHeight(profileHeight: profileHeights[id])
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.titlebarPrefetchInFlight = false
                guard self.titlebarPrefetchGeneration == generation,
                      self.titlebarDoubleClickEnabled, mayBeTitlebar else { return }
                Task { @MainActor in await ShareableContentCache.shared.prefetch() }
            }
        }
    }

    // 连续点击只在停顿后请求一次后台 AX 解析；全局 monitor 与菜单路径都不会
    // 同步等待它。真正置顶动作会强制拿到新 target 后才继续。
    private func schedulePinnedPreviewTargetRefresh() {
        pinnedPreviewTargetRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pinnedPreviewTargetRefreshWorkItem = nil
            self?.refreshPinnedPreviewTarget(reason: "global-mouse-down")
        }
        pinnedPreviewTargetRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }









    func focusSizedFrame(pos: CGPoint, size: CGSize,
                                 visible: NSRect, areaRatio: CGFloat,
                                 canResize: Bool) -> NSRect {
        guard canResize, size.width > 1, size.height > 1 else {
            let width = min(size.width, visible.width)
            let height = min(size.height, visible.height)
            return NSRect(x: visible.midX - width / 2,
                          y: visible.midY - height / 2,
                          width: width,
                          height: height)
        }
        if areaRatio >= 0.999 {
            return NSRect(x: round(visible.minX),
                          y: round(visible.minY),
                          width: round(visible.width),
                          height: round(visible.height))
        }

        let aspect = size.width / size.height
        let targetArea = max(1, visible.width * visible.height * areaRatio)
        var width = sqrt(targetArea * aspect)
        var height = width / aspect
        if width > visible.width {
            width = visible.width
            height = width / aspect
        }
        if height > visible.height {
            height = visible.height
            width = height * aspect
        }
        width = min(max(width, min(size.width, visible.width, 420)), visible.width)
        height = min(max(height, min(size.height, visible.height, 260)), visible.height)
        return NSRect(x: visible.midX - width / 2,
                      y: visible.midY - height / 2,
                      width: round(width),
                      height: round(height))
    }


    func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,
                                              appName: String, title: String) {
        let displayTitle = descriptiveDisplayTitle(appName: appName, windowTitle: title)
        // 收成缩略图的：读屏先说要做什么，再说是谁（"展开窗口：App"）；其余形态照旧。
        let label = overlay.contentView is ShadeThumbnailView
                ? WSL10n.text("bar.a11y.thumbnail", zh: "展开窗口：%@", appName)
                : WSL10n.text("bar.a11y.folded", zh: "已收起的窗口：%@", displayTitle)
        let target = ShadedAccessibilityActionTarget { [weak self] in
            self?.unshade(id) ?? false
        }
        accessibilityActionTargets[id] = target

        let actions = [
            NSAccessibilityCustomAction(name: WSL10n.text("bar.action.unroll", zh: "展开窗口"), target: target,
                                        selector: #selector(ShadedAccessibilityActionTarget.perform(_:)))
        ]
        guard let contentView = overlay.contentView else { return }
        contentView.setAccessibilityElement(true)
        contentView.setAccessibilityRole(NSAccessibility.Role.button)
        contentView.setAccessibilityLabel(label)
        contentView.setAccessibilityValue(WSL10n.text("say.rolledUp", zh: "已收起"))
        contentView.setAccessibilityHelp(WSL10n.text("bar.a11y.unrollHelp", zh: "展开这个窗口"))
        contentView.setAccessibilityCustomActions(actions)
    }

    // 动态翻转折叠项标题，与 ⌃⌘C 实际行为一致。这里绝不能为菜单文案同步读
    // focusedWindow：忙 app 的 AX timeout 会把每一次菜单重建卡住。使用置顶预览
    // 控制器维护的后台 target 快照；快照尚未就绪时宁可显示保守的"折叠"。

    func currentShadedOverlayID() -> CGWindowID? {
        let activeWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        for window in activeWindows {
            if let entry = shaded.first(where: { $0.value.overlay === window }) {
                return entry.key
            }
        }

        let mouse = NSEvent.mouseLocation
        let hits = shaded.compactMap { id, state -> (CGWindowID, NSWindow)? in
            guard let overlay = state.overlay,
                  overlay.frame.insetBy(dx: -3, dy: -3).contains(mouse) else { return nil }
            return (id, overlay)
        }
        return hits.max { $0.1.level.rawValue < $1.1.level.rawValue }?.0
    }


@objc func finishOnboarding() {
        dismissOnboarding()
    }

@objc func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: shadeOnboardingShownDefaultsKey)
        onboardingRefreshTimer?.invalidate()
        onboardingRefreshTimer = nil
        onboardingWindow?.orderOut(nil)
    }




    // 下面这一组只跑 defaults / killall，不读界面状态。Dock 串行队列和退出时的 sync 都直接调用。
    nonisolated private var toolRunner: DockToolRunner { dockToolRunnerOverride ?? .live }

    @discardableResult
    nonisolated private func runTool(_ path: String, _ args: [String]) -> Int32? { toolRunner.run(path, args) }
    nonisolated private func readTool(_ path: String, _ args: [String]) -> String? { toolRunner.read(path, args) }

    nonisolated private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }
    nonisolated private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }
    nonisolated private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect

    nonisolated private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {
        let deadline = Date().addingTimeInterval(6)   // 两次尝试总预算
        for attempt in 1...2 {
            if deadline.timeIntervalSinceNow <= 0 {
                wlog("dock: mineffect write budget exhausted reason=\(reason)")
                break
            }
            let slice = { min(DockToolRunner.defaultTimeout, max(0.1, deadline.timeIntervalSinceNow)) }
            toolRunner.run("/usr/bin/defaults", ["write", "com.apple.dock", "mineffect", "-string", value], timeout: slice())
            let effective = toolRunner.read("/usr/bin/defaults", ["read", "com.apple.dock", "mineffect"], timeout: slice())
            if effective == value {
                wlog("dock: mineffect=\(value) verified reason=\(reason) attempt=\(attempt)")
                return true
            }
            wlog("dock: mineffect verify failed expected=\(value) actual=\(effective ?? "<unset>") reason=\(reason) attempt=\(attempt)")
        }
        return false
    }

    nonisolated private func persistDockMinimizeEffectSession(original: String?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.set(original != nil, forKey: dockMineffectHadOriginalDefaultsKey)
        if let original {
            defaults.set(original, forKey: dockMineffectOriginalDefaultsKey)
        } else {
            defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
        }
    }

    nonisolated private func clearDockMinimizeEffectSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.removeObject(forKey: dockMineffectHadOriginalDefaultsKey)
        defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
    }

    nonisolated private func restoreDockMinimizeEffect(original: String?) {
        if let original {
            runDefaults(["write", "com.apple.dock", "mineffect", "-string", original])
        } else {
            runDefaults(["delete", "com.apple.dock", "mineffect"])
        }
    }

    nonisolated private func recoverStaleDockMinimizeEffectSessionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: dockMineffectSessionActiveDefaultsKey) else { return }
        let hadOriginal = defaults.bool(forKey: dockMineffectHadOriginalDefaultsKey)
        let original = hadOriginal ? defaults.string(forKey: dockMineffectOriginalDefaultsKey) : nil
        restoreDockMinimizeEffect(original: original)
        clearDockMinimizeEffectSession()
        killDock()
        wlog("dock: recovered stale mineffect session original=\(original ?? "<unset>")")
    }

    private func enableScaleMinimizeEffectForSession() {
        guard !scaleMinimizeActive, !dockOperationInFlight else { return }
        dockOperationInFlight = true
        dockWorkQueue.async { [weak self] in
            guard let self else { return }
            self.recoverStaleDockMinimizeEffectSessionIfNeeded()
            let original = self.readDefaults(["read", "com.apple.dock", "mineffect"])
            let originalWasScale = original == "scale"
            if !originalWasScale {
                self.persistDockMinimizeEffectSession(original: original)
            } else {
                self.clearDockMinimizeEffectSession()
            }
            let verified = self.writeDockMinimizeEffect("scale", reason: "session-start")
            // Even when defaults already says "scale", the running Dock process may
            // still be using Genie until it reloads preferences. Restarting Dock here
            // makes WindowShade's minimize fallback match the product metaphor.
            self.killDock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dockOperationInFlight = false
                self.originalDockMinimizeEffect = original
                self.dockMinimizeEffectChanged = verified && !originalWasScale
                self.scaleMinimizeActive = true
            }
        }
    }

    private func restoreDockMinimizeEffect() {
        // 恢复基于持久化的 session 键而不是实例状态：与在途的 enable 在同一个
        // 串行队列上按 FIFO 执行，天然得到「先启用后还原」的正确顺序。
        dockWorkQueue.async { [weak self] in
            guard let self else { return }
            self.recoverStaleDockMinimizeEffectSessionIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dockOperationInFlight = false
                self.originalDockMinimizeEffect = nil
                self.dockMinimizeEffectChanged = false
                self.scaleMinimizeActive = false
            }
        }
    }


    func currentOperationState(_ id: CGWindowID) -> WindowShadeState {
        operationStates[id] ?? .normal
    }

    // 状态机唯一入口：非法转换拒绝并记日志，避免窗口状态损坏。
    @discardableResult
    func transitionOperationState(id: CGWindowID, to next: WindowShadeState,
                                          reason: String) -> Bool {
        let current = currentOperationState(id)
        guard current.canTransition(to: next) else {
            wlog("state: illegal transition \(current.rawValue) -> \(next.rawValue) id=\(id) reason=\(reason)")
            return false
        }
        operationStates[id] = next
        wlog("state: \(current.rawValue) -> \(next.rawValue) id=\(id) reason=\(reason)")
        return true
    }


    func applicationWillTerminate(_ note: Notification) {
        // 声明收尾：手上还剩什么一起还掉，并把这一轮的「取得/释放/超上限」计数留在日志里。
        appNapActivity.releaseAll()
        inputController.shutdown()
        MainActor.assumeIsolated { ws2Runtime.stop() }
        MainActor.assumeIsolated { UpdaterController.shared.applicationWillTerminate() }
        MainActor.assumeIsolated { pip.shutdown(); slideOver.shutdown() }
        MainActor.assumeIsolated { HabitCenter.shared.stop() }
        duoController.stop()
        windowBrowserController?.stop()
        restoreAll()
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        if let pinnedPreviewFocusMonitor {
            NSEvent.removeMonitor(pinnedPreviewFocusMonitor)
            self.pinnedPreviewFocusMonitor = nil
        }
        pinnedPreviewController.stopAllPreviews(reason: "terminate")
        MainActor.assumeIsolated { silentPrivacyCover.clear() }
        eventTapReenableWorkItem?.cancel()
        eventTapReenableWorkItem = nil
        // 退出前还原 Dock 偏好：同步等在途子进程排空，再按持久化 session 键
        // 恢复（session 键在改动前写入，异步启用/恢复交错下也正确）。
        // 有时限：Dock 工具卡住时不拖死退出；超时就保留 session 键，下次启动由
        // recoverStaleDockMinimizeEffectSessionIfNeeded 修复。
        let dockRestored = DockToolRunner.runBounded(on: dockWorkQueue, timeout: 3) { [weak self] in
            self?.recoverStaleDockMinimizeEffectSessionIfNeeded()
        }
        if !dockRestored { wlog("dock: terminate restore timed out, session key kept for next launch") }
        scaleMinimizeActive = false
        WindowShadeLogger.shared.flushAndClose()
    }

    @discardableResult
    func ensureAccessibility() -> Bool {
        // kAXTrustedCheckOptionPrompt 的值；系统把那个常量导入成了可变全局变量，并发检查下不能直接读。
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: 触发

    @objc func toggleAction() { toggle() }

    // ⌃⌘C 的"当前窗口"必须在用户正看着的 Space 上。切换 Space 后未点击任何窗口时，
    // 前台 app 的 AX 聚焦窗口可能还留在原 Space；直接折叠它会作用于一个不可见窗口，
    // 后续的激活/聚焦还可能把系统拽回那个 Space。这里在当前 Space 上按 z 序找该 app
    // 的最前真实窗口作为替代目标。


    // 每轮 runloop 折叠的时间预算。超过就让出主线程，下一轮继续。
    let focusFoldFrameBudget: TimeInterval = 0.12

    @objc func focusCurrentAppAction() {
        // 这条路径会同步折叠其它 App 的全部窗口，是主线程上最长的一段工作：
        // 自报耗时，并让卡顿哨兵能把阻塞归因到它。
        // 级联进行中再按一次会让两次专注交叉修改同一份会话状态，直接忽略。
        guard !focusCascadeActive else {
            wlog("focus: 折叠仍在进行中，忽略本次请求")
            return
        }
        let before = axWindowListEnumerations
        foldPhaseTotals.removeAll()
        logIfSlow("focus: 专注当前 App", threshold: 0.2) { focusCurrentAppCycle() }
        wlog("focus: 主线程 AX 窗口列表枚举 \(axWindowListEnumerations - before) 次（每次约 20ms）")
    }

    @objc func unshadeFromMenu(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        unshade(CGWindowID(n.uint32Value))
    }

    @objc func quit() {
        restoreAll()
        NSApp.terminate(nil)
    }

    // MARK: 全局快捷键




    // MARK: 双击标题栏（CGEventTap）

    // tap 创建需要辅助功能权限；权限可能晚于启动才授予，所以轮询到授权后再装。
    func setupEventTapWhenTrusted() {
        if setupEventTap() {
            rescueOffscreenWindows(silent: true, announceRestored: true)
            startEnvironmentWatch()
            return
        }
        tapSetupTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            // 这个计时器是在主线程方法里挂上当前 run loop 的，到点仍在主线程。
            // 计时器本身留在闭包原来的隔离域里停掉，不送进主线程闭包。
            let installed = MainActor.assumeIsolated { () -> Bool in
                guard self?.setupEventTap() == true else { return false }
                self?.rescueOffscreenWindows(silent: true, announceRestored: true)
                self?.startEnvironmentWatch()
                return true
            }
            if installed { t.invalidate() }
        }
    }

    // tap 因输入洪泛被系统禁用时退避重启用，避免反复禁用/启用和系统打架。

    @discardableResult
    func setupEventTap() -> Bool {
        guard eventTap == nil, AXIsProcessTrusted() else { return eventTap != nil }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: eventTapCallback, userInfo: nil) else { return false }
        eventTap = tap
        mouseDownTapPort = tap
        EventTapHealth.shared.register(tap, label: "titlebar-click")
        // 钩子跑在自己的线程上：主线程卡住时，全系统的单击不用等它（见 eventTapCallback）。
        let thread = Thread {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "WindowShade.mouse-down-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    // MARK: 睡醒后的恢复（规格 R3）

    /// 睡醒（整机或屏幕）后分三档恢复：立即、0.2 秒、0.8 秒（WakeRecoveryPlan）。
    /// 「睡一觉醒来某样功能没回来」是同类工具更新日志里最多的一类；系统各部分醒来有先后，
    /// 一次检查可能太早。每档只重开登记了、却被停掉的 tap，所以重复执行无害；再次睡醒会取消没跑完的档。
    /// 各处原有的唤醒观察者（暂停/恢复各自的计时器）保持不变。
    private func startWakeRecovery() {
        guard wakeRecoveryObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.didWakeNotification, "wake"),
                               (NSWorkspace.screensDidWakeNotification, "screens-wake")] {
            wakeRecoveryObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runWakeRecovery(reason: reason) }
            })
        }
    }

    private func runWakeRecovery(reason: String) {
        wakeRecoveryWork.forEach { $0.cancel() }
        let stages = WakeRecoveryPlan.delays.count
        wakeRecoveryWork = WakeRecoveryPlan.delays.enumerated().map { stage, delay in
            let work = DispatchWorkItem {
                let reenabled = EventTapHealth.shared.sweep(reason: "wake-recovery")
                SystemLog.input.info("wake-recovery \(reason, privacy: .public) stage \(stage + 1)/\(stages) re-enabled=\(reenabled.count)")
                wlog("wake-recovery: \(reason) stage \(stage + 1)/\(stages) "
                     + (reenabled.isEmpty ? "all taps running" : "re-enabled \(reenabled)"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    // MARK: 装好之后的周期体检

    /// 事件通道与权限的周期体检（5 秒一次）。
    ///
    /// 为什么需要它：系统会在**回调超时**或**输入洪泛**时把 tap 静默停掉——没有通知、没有报错，
    /// 只是从此不再送事件。我们现在只在收到 `tapDisabledByTimeout`／`tapDisabledByUserInput`
    /// 时才重开（GlobalInputFilter、ScrollTap、WindowSwitcher、TrackpadGestures、
    /// NotchLevelObserver 五处），所以**在没有那两个事件的情况下死掉，我们不查**。
    ///
    /// 这一条是照着两家成熟实现补的：DockDoor 的 5 秒看门狗里就有一项 `CGEvent.tapIsEnabled`
    /// 检查、为假则重建；Wins 把 `missionControl.tapDisabled` 当成一个专门的埋点。
    /// 间隔取 5 秒：够快能自愈，够慢不打扰。
    private func startEnvironmentWatch() {
        guard environmentWatch == nil else { return }
        environmentWatch = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runEnvironmentCheck() }
        }
        lastAccessibilityTrusted = AXIsProcessTrusted()
    }

    private func runEnvironmentCheck() {
        // 一、通道还活着吗。查登记表里的全部 tap（9 支，见 EventTapHealth），只重开同一支 port
        // （不重建、不新起线程），与各处 tapDisabledBy* 的处理保持同一形状；主人关掉的不碰。
        let reenabled = EventTapHealth.shared.sweep(reason: "environment")
        if !reenabled.isEmpty {
            SystemLog.input.notice("event taps disabled silently, re-enabled \(reenabled.joined(separator: ","), privacy: .public)")
            tapSilentStops += reenabled.count
            wlog("environment: event taps were disabled silently, re-enabled \(reenabled) (count=\(tapSilentStops))")
        }
        // 二、权限还在吗。从「有」变「无」时所有窗口动作都还在跑，但没有一件能生效，且不报错——
        // 这种「静默失灵」最难排查，所以要告诉人（规格 R2，对照 WindowMizer 的同一条）。
        // 只在状态变化的那一拍说一次：刘海能说就在刘海说，点一下去授权；说不了就退回菜单栏标题。
        // 菜单顶上另有一行「打开辅助功能…」，权限回来之前一直在（MenuBarController 的动态行）。
        let trusted = AXIsProcessTrusted()
        if lastAccessibilityTrusted, !trusted {
            SystemLog.permissions.notice("accessibility revoked")
            quietNotice(PrivacyPaneName.adjust(WSL10n.text("notice.accessibility.revoked", zh: "辅助功能被关掉了，收起和移动窗口暂时不生效")),
                        kind: .needsPermission,
                        log: "environment: accessibility permission was revoked, window actions will no longer take effect")
            rebuildMenu()
        } else if !lastAccessibilityTrusted, trusted {
            SystemLog.permissions.notice("accessibility back")
            if eventTap == nil { _ = setupEventTap() }
            quietNotice(PrivacyPaneName.adjust(WSL10n.text("notice.accessibility.back", zh: "辅助功能打开了，收起和移动窗口恢复了")),
                        kind: .done, log: "environment: accessibility permission is back")
            rebuildMenu()
        }
        lastAccessibilityTrusted = trusted
    }

}
