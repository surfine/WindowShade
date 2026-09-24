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
let shadeSoundChoices: [(label: String, name: String)] = [
    ("柔和（Purr）", "Purr"),
    ("低调（Submarine）", "Submarine"),
    ("轻吹（Blow）", "Blow"),
    ("细微轻响（Tink）", "Tink"),
    ("玻璃（Glass）", "Glass"),
    ("弹开（Pop）", "Pop")
]
var appDelegate: AppDelegate?

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
    // 阻塞数秒。快照在后台按 app 并行采集，主线程仅应用已经完成的结果。
    struct ReconcileAXTarget {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let needsMinimizedState: Bool
    }

    struct ReconcileAXSnapshot {
        let id: CGWindowID
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
    var reconcileTimer: Timer?
    var isReconcilingShadedWindows = false
    let reconcileAXWorkQueue = DispatchQueue(label: "WindowShade.reconcile-ax", qos: .utility)
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
    var windowBrowserController: WindowBrowserController?
    var windowBrowserHotKeyRef: EventHotKeyRef?
    var menuRebuildWorkItem: DispatchWorkItem?
    var suppressMenuRebuilds = false
    var pendingMenuRebuild = false
    var isUpdatingMenuFromDelegate = false
    private var pinnedPreviewFocusMonitor: Any?
    private var pinnedPreviewTargetRefreshWorkItem: DispatchWorkItem?
    var spaceRefreshWorkItem: DispatchWorkItem?
    private var appNapActivity: NSObjectProtocol?
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
        if UserDefaults.standard.object(forKey: shadeSoundEnabledDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeSoundEnabledDefaultsKey)
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
    /// 带到每张桌面：窗口留在自己的桌面，别的桌面上看得到它的卷帘条。
    lazy var carry = MainActor.assumeIsolated { CarryController(owner: self) }
    lazy var gestures = MainActor.assumeIsolated { TrackpadGestureController(owner: self) }
    lazy var pinnedPreviewController = PinnedPreviewController(
        notice: { [weak self] message, log in
            self?.quietNotice(message, log: log)
        },
        sessionsDidChange: { [weak self] in
            self?.scheduleMenuRebuild()
        }
    )

    func applicationDidFinishLaunching(_ note: Notification) {
        // 代理应用也要有标准主菜单：文本编辑快捷键与 ⌘W 都靠它的 key equivalent 派发。
        installStandardMainMenu()
        duoController.start(owner: self)
        let sessionFormatter = DateFormatter()
        sessionFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sessionFormatter.locale = Locale(identifier: "en_US_POSIX")
        wlog("=== session start pid=\(getpid()) at \(sessionFormatter.string(from: Date())) ===")
        // 永久退出 App Nap：本进程持有全局 CGEventTap（回调在主 RunLoop 执行），
        // 被 nap 后每次双击都会拖慢全系统鼠标事件直到 tap 被系统超时禁用；
        // 计时器（reconcile/watchdog/菜单刷新）也会被合并推迟数十秒。
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "WindowShade owns a global event tap; App Nap stalls system-wide mouse input")
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
        logIfSlow("launch gestures", threshold: 0.1) {
            MainActor.assumeIsolated { gestures.refreshMonitors() }
        }
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
        // 浅深色切换没有公开的 NSApplication 通知：用 KVO 观察 effectiveAppearance，
        // 变化时同样只刷新材质与边线。
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            self?.systemAppearanceOptionsChanged(
                Notification(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification))
        }
    }

    /// 辅助功能外观变化：只刷新材质/边线/阴影，不动窗口状态、不触发任何捕获。
    @objc func systemAppearanceOptionsChanged(_ note: Notification) {
        dispatchPrecondition(condition: .onQueue(.main))
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
    // 不会再形成“刷新 → rebuild → 再刷新”的同步 AX 放大链路。
    func refreshPinnedPreviewTarget(reason: String) {
        pinnedPreviewController.refreshCurrentTarget(reason: reason) { [weak self] _, didChange in
            guard didChange else { return }
            self?.scheduleMenuRebuild()
        }
    }

    private func setupPinnedPreviewFocusTracking() {
        refreshPinnedPreviewTarget(reason: "launch")
        pinnedPreviewFocusMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // 标题栏带内的首次按下就预热窗口枚举缓存（监视器回调是异步投递，
            // 不在 tap 关键路径上）：双击折叠的第二下落地时 SCShareableContent
            // 通常已就绪，卷帘条"点了要等"的感知延迟显著缩短。
            if #available(macOS 14.0, *), event.type == .leftMouseDown,
               self?.titlebarDoubleClickEnabled == true {
                let mouse = NSEvent.mouseLocation
                let cgPoint = CGPoint(x: mouse.x, y: coordinateBaselineY() - mouse.y)
                if pointMayLieInTitlebarBand(cgPoint) {
                    Task { @MainActor in await ShareableContentCache.shared.prefetch() }
                }
            }
            self?.schedulePinnedPreviewTargetRefresh()
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









    let focusMotionDuration: TimeInterval = 0.065

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
        let label = "已收起的窗口：\(displayTitle)"
        let target = ShadedAccessibilityActionTarget { [weak self] in
            self?.unshade(id) ?? false
        }
        accessibilityActionTargets[id] = target

        let actions = [
            NSAccessibilityCustomAction(name: "展开窗口", target: target,
                                        selector: #selector(ShadedAccessibilityActionTarget.perform(_:)))
        ]
        guard let contentView = overlay.contentView else { return }
        contentView.setAccessibilityElement(true)
        contentView.setAccessibilityRole(NSAccessibility.Role.button)
        contentView.setAccessibilityLabel(label)
        contentView.setAccessibilityValue("已收起")
        contentView.setAccessibilityHelp("展开这个窗口")
        contentView.setAccessibilityCustomActions(actions)
    }

    // 动态翻转折叠项标题，与 ⌃⌘C 实际行为一致。这里绝不能为菜单文案同步读
    // focusedWindow：忙 app 的 AX timeout 会把每一次菜单重建卡住。使用置顶预览
    // 控制器维护的后台 target 快照；快照尚未就绪时宁可显示保守的“折叠”。

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




    @discardableResult
    private func runTool(_ path: String, _ args: [String]) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do {
            try p.run()
        } catch {
            wlog("tool: failed to run \(path) \(args.joined(separator: " ")) error=\(error)")
            return nil
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            wlog("tool: nonzero status=\(p.terminationStatus) \(path) \(args.joined(separator: " "))")
        }
        return p.terminationStatus
    }

    private func readTool(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }
    private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }
    private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect

    private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {
        for attempt in 1...2 {
            runDefaults(["write", "com.apple.dock", "mineffect", "-string", value])
            let effective = readDefaults(["read", "com.apple.dock", "mineffect"])
            if effective == value {
                wlog("dock: mineffect=\(value) verified reason=\(reason) attempt=\(attempt)")
                return true
            }
            wlog("dock: mineffect verify failed expected=\(value) actual=\(effective ?? "<unset>") reason=\(reason) attempt=\(attempt)")
        }
        return false
    }

    private func persistDockMinimizeEffectSession(original: String?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.set(original != nil, forKey: dockMineffectHadOriginalDefaultsKey)
        if let original {
            defaults.set(original, forKey: dockMineffectOriginalDefaultsKey)
        } else {
            defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
        }
    }

    private func clearDockMinimizeEffectSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.removeObject(forKey: dockMineffectHadOriginalDefaultsKey)
        defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
    }

    private func restoreDockMinimizeEffect(original: String?) {
        if let original {
            runDefaults(["write", "com.apple.dock", "mineffect", "-string", original])
        } else {
            runDefaults(["delete", "com.apple.dock", "mineffect"])
        }
    }

    private func recoverStaleDockMinimizeEffectSessionIfNeeded() {
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
        eventTapReenableWorkItem?.cancel()
        eventTapReenableWorkItem = nil
        // 退出前还原 Dock 偏好：同步等在途子进程排空，再按持久化 session 键
        // 恢复（session 键在改动前写入，异步启用/恢复交错下也正确）。
        dockWorkQueue.sync {
            recoverStaleDockMinimizeEffectSessionIfNeeded()
        }
        scaleMinimizeActive = false
        WindowShadeLogger.shared.flushAndClose()
    }

    @discardableResult
    func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
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
            rescueOffscreenWindows(silent: true)
            return
        }
        tapSetupTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            if self?.setupEventTap() == true {
                self?.rescueOffscreenWindows(silent: true)
                t.invalidate()
            }
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
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

}
