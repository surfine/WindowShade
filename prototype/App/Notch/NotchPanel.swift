// // 刘海面板窗口本体：岛窗口的层级、形状与命中（画布是 NotchCanvasView，内容是 NotchContentView）。

import Cocoa
import ApplicationServices

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
        /// 编程会话右耳的样子（转圈加项目名、琥珀点加“等你”、个数加状态点）。nil = 不是会话，或额度那两种。
        var sessionFace: NotchSessionEar.Face? = nil
        /// 请求交回终端、助手在那边等人时，右耳琥珀点的读屏句；其它时候是 nil。
        var sessionSpoken: String? = nil
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
                && sessionFace == other.sessionFace && sessionSpoken == other.sessionSpoken
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
    /// 点最小形（小圆）：打开它那件活动的 App（不和紧凑那件互换）。
    var onMinimumTap: ((String) -> Void)?
    var onActivityAction: ((NotchActivityAction) -> Void)?
    var canSwipeActivities: (() -> Bool)?
    /// 那一排收起时，里面摆过结束了的活动：看过了，控制器据此调 `rowSeen()`。
    var onRowSeen: (() -> Void)?
    var onLongPress: (() -> Void)?
    /// 两指在刘海上张开：展开那一排；主屏幕开着时照旧是返回（控制器决定）。
    var onSpread: (() -> Void)?
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
        case .launchpad, .windowBrowser, .conductor, .pomodoro, .countdownTimer, .calendarCard, .nowPlaying,
             .agentReview, .ownedCodex, .ownedModelPicker, .silent, .faceEnrollment, .faceRecognition:
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
    /// `retreating`：被收走的是编程会话审批卡，先让它缩回琥珀点（视图由画布留到播完）。
    func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true, retreating: Bool = false) {
        canvas.resetInteractions()
        pressWork?.cancel(); pressWork = nil
        hoverTimer?.invalidate(); pulled = 0; pushed = 0
        alertTimer?.invalidate(); alertInfo = nil
        if dropState != .none { noteDropInteraction(false) }
        dropState = .none; stripLanding = false
        authenticationView = view
        canvas.setAuthentication(view, retreating: retreating && animated)
        updateVisibility(); apply(animated: animated)
    }
    /// 形状探针：此刻挂着的活动（有活动时岛停在紧凑，量不到静止态），以及暂时清空、事后放回。
    var activitiesForProbe: (items: [NotchActivity], selected: String?) { (activityItems, activitySelection) }

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
    /// 系统的 » 在（图标太多被藏起来）：悬停只认点击。量菜单栏的人（LA-0 / NotchWatch）知道了再设；没人设就当不在。
    var menuBarOverflowShown = false
    /// 两指往下拉了多少（点）。
    private var pulled: CGFloat = 0
    /// 两指往上推了多少（点，向上为正）。推过 NotchPushUp.commitTravel 岛上出现“松手全部收进刘海”。
    private var pushed: CGFloat = 0
    /// 往上推是“全部收进刘海”吗（主屏幕开着时上推仍是返回，沿用老规则）。
    var pushIsTuck: (() -> Bool)?
    /// 岛这一刻因为拉或推多长出来的高度（点）；都没有为 0。
    private var trayExtra: CGFloat {
        if pulled > 0 { return Self.rubberBand(pulled, limit: (canPull?() ?? false) ? 84 : 18) }
        if pushed > 0 { return Self.rubberBand(pushed, limit: NotchPushUp.followLimit) }
        return 0
    }
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
    private var tiles: [NotchTile] = []
    private let canvas: NotchCanvasView
    private var hoverTimer: Timer?
    private var settleGeneration = 0
    /// 最近一次停稳的是哪一次变形（探针用：等到这一次真的停下、面板缩回、肩换好了再量）。
    private var settledGeneration = 0
    var isSettledForProbe: Bool { settledGeneration == settleGeneration }
    /// 形状探针停不下来时，说清是谁撑着岛。
    var stateForProbe: String {
        "compact \(compact.map { "count \($0.count)" } ?? "nil") display \(displayCompact().map { "count \($0.count) leading \($0.leading ?? "-")" } ?? "nil") meter \(meter != nil) flash \(powerFlashState != nil) alert \(alertInfo != nil) expanded \(isExpanded) pulled \(pulled) drop \(dropState) gen \(settledGeneration)/\(settleGeneration)"
    }

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
        canvas.onPush = { [weak self] distance, touching in self?.push(distance, touching: touching) }
        canvas.pushIsTuck = { [weak self] in self?.pushIsTuck?() ?? false }
        canvas.onNavigation = { [weak self] destination in
            if destination == .back { self?.collapse() }
            self?.onNavigation?(destination)
        }
        canvas.onSpread = { [weak self] in self?.onSpread?() }
        canvas.onPress = { [weak self] clicks in self?.pressed(clicks) }
        canvas.onEarTap = { [weak self] isMusic in
            guard let self else { return }
            // 正在播放的耳朵照 NP-4 长成大卡；其余活动打开它自己的 App 或卡（同一个“打开”动作）。
            if isMusic { self.openNowPlayingCard() } else { self.onActivityAction?(.open) }
        }
        canvas.onMinimumTap = { [weak self] id in self?.onMinimumTap?(id) }
        canvas.onFiles = { [weak self] files in
            guard let self else { return }
            self.onFiles?(files, self.notch)
        }
        canvas.registerForDraggedTypes([.fileURL])
        canvas.onIslandDrag = { [weak self] info, phase in self?.islandDrag(info, phase) ?? [] }
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
                                      ongoing: $0.kind.isOngoing, away: $0.kind.isAway, session: $0.kind == .session,
                                      spoken: $0.ongoing?.spoken ?? $0.away?.spoken,
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
            endKeyboardPeek()
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
        case .peek(let id):
            // 空格：看一眼亮着的这一格；再按一次收起。只有窗口格有（正在进行的格、离开期间的非窗口格没有）。
            if keyboardPeekID == id { keyboardPeekID = nil; onTileHover?(id, false, nil); return true }
            keyboardPeekID = id
            onTileHover?(id, true, canvas.tileScreenRect(id))
        case .activate(let id):
            endKeyboardPeek()
            // 和指针点一下同一条路：onTileClicked → NotchController.open（放回、去、还原，flyOut 弹簧），之后这一排收起。
            if !canvas.activateTile(id) { onTileClicked?(id, nil) }
        case .end:
            endKeyboardPeek()
            wlog("notch: focus end")
            collapse()
        }
        return true
    }

    private var keyboardPeekID: CGWindowID?
    private func endKeyboardPeek() {
        guard let id = keyboardPeekID else { return }
        keyboardPeekID = nil
        onTileHover?(id, false, nil)
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
        guard focus.isActive else {
            // 岛接着键盘、那一排没展开时：空格 = 长按，Return = 点（稿「怎么点、怎么按」，暂定）。
            let command = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            switch IslandInteraction.key(forKeyCode: event.keyCode, hasCommandModifiers: command) {
            case .longPress?: if onHold?() != true { onLongPress?() }
            case .press?: pressed(1)
            case nil: super.keyDown(with: event)
            }
            return
        }
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
    /// 摄像头正被任何 App 用着（视频通话）：自己长大的提醒只留一个点（第 40 条）。由 NotchController 接上；默认没有。
    var cameraInUse: () -> Bool = { false }

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
        updateVisibility()
        apply(animated: true, roomOnly: roomOnly)
    }

    /// 紧凑样式在刘海左右各占多宽：最宽 34 点；两边空位不够时收窄，最窄 26 点（图标 18 点、两边各 4 点），
    /// 再窄就放到刘海下面（WWDC23：紧凑样式尽量窄，不留空白）。
    static let sideWidth: CGFloat = IslandMetrics.compactEarWidth
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

    /// 提醒展开后有多宽：照系统的岛，提醒和教手势都是展开的上限 408（暂定，iOS 尺寸，数字在 IslandMetrics）。
    static func alertWidth(notch: NSRect, teaching: Bool) -> CGFloat {
        IslandMetrics.expandedWidth
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
    /// `admitted`：队列路径已经过协调器准入，这里不再问第二遍（问了会把同一句记两次账）。
    func alert(_ info: Alert, duration: TimeInterval = Motion.Hold.alert, admitted: Bool = false) {
        // 你正在按音量亮度键（交互层）：这一句变成一个点并消耗掉，不回来补说。
        if meter != nil, !isAuthenticating {
            if !admitted, let leases, let displayID { _ = leases.remind(on: displayID) }
            showsSecondaryDot = true
            apply(animated: false)
            return
        }
        // 视频通话中（摄像头在用）：不自己长大，这一句变成一个点；你点、长按照常打开。授权的提示不受影响。
        if !isAuthenticating, !CameraQuietPolicy.allowsAutoGrowth(cameraInUse: cameraInUse(), userInitiated: false) {
            if !admitted, let leases, let displayID { _ = leases.remind(on: displayID) }
            showsSecondaryDot = true
            apply(animated: false)
            return
        }
        let blocked = isAuthenticating || isExpanded || dropState != .none
        if blocked {
            if !admitted, let leases, let displayID { _ = leases.remind(on: displayID) }
            pullSecondaryDot()
            return
        }
        if !admitted, let leases, let displayID, !leases.remind(on: displayID) {
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
        // 面板本地的输入也报给协调器：不占租约，但提醒要让（两耳期间来的提醒只留点）。
        if let displayID { leases?.noteHostInteraction(on: displayID, holdMilliseconds: UInt64((Motion.Hold.level + 1.0) * 1000)) }
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
        guard CameraQuietPolicy.allowsAutoGrowth(cameraInUse: cameraInUse(), userInitiated: false) else { return false }
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
        if let displayID { leases?.endHostInteraction(on: displayID) }
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
        // 照系统的岛：岛宽固定，格子全部排出，放不下就左右滚（NotchContentView），不再按屏宽少放几张。
        let away = tiles.filter { $0.kind.isAway }
        let windows = tiles.filter { !$0.kind.isOngoing && !$0.kind.isAway }
        let ongoing = tiles.filter { $0.kind.isOngoing }
        let fit = NotchRow.fit(windows: windows.count, ongoing: ongoing.count,
                               tail: ongoing.contains { $0.ongoing?.shelfCount != nil }, away: away.count)
        self.tiles = away + Array(windows.prefix(fit.windows)) + Array(ongoing.prefix(fit.ongoing))
        if focus.isActive {
            // 键盘焦点在时，那一排被重新排过（缩略图之外的内容变了）：焦点还在就留着，没了重选。
            focus.setCells(focusCells())
            syncFilter()
            canvas.setTileFocus(focus.visibleFocusID, animated: false)
            reportFocusKind()
        }
        updateVisibility()
        apply(animated: animated)
        onRowExpanded?()
    }

    /// 那一排展开了、收起了（离开期间的列表据此停表、清掉）。
    var onRowExpanded: (() -> Void)?
    var onRowCollapsed: (() -> Void)?

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
        onRowCollapsed?()
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
                self.noteDropInteraction(false)
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
        fileArmGate.reset()
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
        let rawHit = shown ? FileDropGeometry.hit(pointer, island: island) : FileDropHit.outside
        // 进了岛要停满 MotionHold.dropDwellSeconds 才亮起（快速划过不亮）；亮起前岛只是垂着（.offered）。
        let now = CACurrentMediaTime()
        let wantsArm = shown && rawHit != .outside
        let armed = fileArmGate.update(inside: wantsArm, now: now)
        fileArmRecheck?.cancel(); fileArmRecheck = nil
        if wantsArm, !armed, let wait = fileArmGate.remaining(now: now) {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.updateFileDrop(pointer: pointer) }
            }
            fileArmRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.005, execute: work)
        }
        let hit = armed ? rawHit : FileDropHit.outside
        setFileDropState(shown ? (hit == .outside ? .offered : .armed) : .none, hit: hit, model: model)
    }
    private var fileArmGate = DropDwellGate()
    private var fileArmRecheck: DispatchWorkItem?

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
        fileArmGate.reset(); fileArmRecheck?.cancel(); fileArmRecheck = nil
        let wasShown = fileDrop != nil && dropState != .none
        let had = fileDrop != nil
        fileDrop = nil
        canvas.islandDragActive = false
        if had { canvas.registerForDraggedTypes([.fileURL]) }
        if wasShown {
            dropState = .none
            noteDropInteraction(false)
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
        noteDropInteraction(state != .none)
        updateVisibility()
        apply(animated: true)
    }

    /// 落点进行与否报给协调器（面板本地的输入，不占租约，但提醒要让）。
    private func noteDropInteraction(_ active: Bool) {
        guard let displayID else { return }
        if active { leases?.noteHostInteraction(on: displayID, holdMilliseconds: 4_000) }
        else { leases?.endHostInteraction(on: displayID) }
    }

    /// 卷轴概览里拖着一扇窗靠近刘海（SS-04）：长成落点（用 catch 弹簧），离开用 calm 收回。
    /// 正在认证 / 放行占着、别的落点正在进行时不出（Core 里 approvalHolding 也会让松手不收）。
    func setStripLanding(_ on: Bool) {
        if on {
            guard !stripLanding, !isAuthenticating, dropState == .none, fileDrop == nil else { return }
            stripLanding = true
            dropState = .offered
            noteDropInteraction(true)
            if !Motion.reduced { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            updateVisibility()
            apply(animated: true)
        } else {
            guard stripLanding else { return }
            stripLanding = false
            if dropState == .offered {
                dropState = .none
                noteDropInteraction(false)
            }
            updateVisibility()
            apply(animated: true, spring: Self.calmSpring)
        }
    }

    private static var calmSpring: NotchCanvasView.Spring {
        let calm = Motion.reduced ? Motion.Spring.reducedNotch : Motion.Spring.calm
        return NotchCanvasView.Spring(response: calm.response, bounce: calm.bounce, initialVelocity: 0)
    }

    /// 指针进出。照系统的岛：指针停在刘海上不再展开那一排（改成长按，见 onLongPress）。
    /// 进来：那一排已经展开着就马上通知（刷新格子）；没展开就停够 0.12 秒再通知，控制器只用它教一下刘海能做什么（从菜单栏划过去不算）。
    /// 出去：立刻通知，展开着的那一排随之收起。
    private func hover(_ inside: Bool) {
        guard !isAuthenticating else { return }
        focusPointer(inside)
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard inside else {
            onHoverChanged?(false)
            return
        }
        if IslandInteraction.hoverNotifiesImmediately(isExpanded: isExpanded) {
            onHoverChanged?(true)
            return
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Motion.Hold.notchDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hoverTimer = nil
                self?.onHoverChanged?(true)
            }
        }
    }

    /// 两指往下拉（见 NotchCanvasView.scrollWheel）：手指在上面时岛一比一跟着长，松手时按速度推算落点。
    /// 两指往上推：岛跟着手指一点点长出来（橡皮筋），推过线出现提示，松手或拉回线下就收回去。
    /// 收不收由画布在松手时按 NotchPushUp 定；这里只管画。
    private func push(_ distance: CGFloat, touching: Bool) {
        guard !isAuthenticating, pushIsTuck?() == true else {
            if pushed != 0 { pushed = 0; apply(animated: true) }
            return
        }
        if touching {
            guard distance != pushed else { return }
            pushed = distance
            hoverTimer?.invalidate()
            apply(animated: false)
            return
        }
        guard pushed != 0 else { return }
        pushed = 0
        let pullSpring = Motion.reduced ? Motion.Spring.reducedNotch : Motion.Spring.pull
        apply(animated: true, spring: NotchCanvasView.Spring(response: pullSpring.response, bounce: pullSpring.bounce,
                                                            initialVelocity: 0))
    }

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
        let away = shown.filter { $0.kind.isAway }
        return NotchRow.layout(windows: shown.filter { !$0.kind.isOngoing && !$0.kind.isAway }.count,
                               ongoing: shown.filter { $0.kind.isOngoing }.count,
                               away: away.count, awayNarrow: away.last?.away?.isNarrow == true)
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
        guard !isAuthenticating, !isExpanded, dropState == .none, alertInfo == nil, meter == nil, pulled == 0, pushed == 0 else { return [] }
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
        if resting, pulled > 0 || pushed > 0 {
            let extra = trayExtra
            rect.origin.y -= extra
            rect.size.height += extra
            if !isVirtual, rect.width < notch.width + 40 { rect = rect.insetBy(dx: -min(20, extra / 3), dy: 0) }
            style.cornerRadius = max(style.cornerRadius, NotchIsland.pullRadius(hardware, extra: extra))
            style.fill = .black
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
            let width: CGFloat
            let height: CGFloat
            if !stacksActivityCard, !tiles.isEmpty {
                // 照系统的岛：那一排固定 408 × 160（从屏幕顶边量起），不随格子数、屏宽变（暂定，iOS 尺寸，IslandMetrics）。
                width = min(IslandMetrics.expandedWidth, screenWidth)
                height = IslandMetrics.rowHeight
            } else {
                // 没有格子的空岛、活动卡叠在窗口上的旧样子：照旧。
                width = min(screenWidth - 44, max(stacksActivityCard ? 420 : notch.width + 120, CGFloat(rowIslandWidth)))
                let rawBelow: CGFloat = stacksActivityCard ? (tiles.isEmpty ? 144 : 286) : (tiles.isEmpty ? 56 : 142)
                height = notch.height + NotchIsland.peninsulaContentHeight(rawBelow)
            }
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
            // 照系统的岛：提醒总高 84、教手势 112，都从屏幕顶边量起。不再走半岛矮档（72 的内容高，总高 100）：
            // 那一档是为避开 WWDC23 10194 的临界高度，系统自己的提醒就是 84，稿的对照账第 6 行定了按稿画。
            let height = teaching ? IslandMetrics.teachingHeight : IslandMetrics.alertHeight
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
                let activitySide = ears.sessionFace.map { NotchSessionEar.earSide(face: $0, earWidth: sideWidth, room: sessionRoom) }
                    ?? NotchRoomPolicy.activitySide(earWidth: sideWidth, leading: room?.leading, trailing: room?.trailing)
                return (compactEarsRect(side: ears.flash != nil ? sideWidth : activitySide),
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
                return (compactEarsRect(side: sideWidth),
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

    /// 紧凑两耳的外框：刘海往左右各长 `side`，高与刘海一致（这台 Mac 的真实尺寸）。
    private func compactEarsRect(side: CGFloat) -> NSRect {
        let height = notch.height
        return NSRect(x: notch.minX - side, y: notch.maxY - height, width: notch.width + 2 * side, height: height)
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
        let bare = !isVirtual && rect == notch && pulled == 0 && pushed == 0
        let resting = !isExpanded && dropState == .none && alertInfo == nil
        let shape = compactShape
        let visual = displayCompact()
        // 半岛展开时保留紧凑左右耳（谁 / 数）在传感器两侧，格子绕着排——相对位置继承，不留额头。
        let shelfEars = isExpanded && (cardItems.isEmpty || mergedRow) && compact != nil
            && dropState == .none && alertInfo == nil && meter == nil
        let compactShown = (resting && visual != nil && (shape != .chin || visual?.leading != nil)) || shelfEars
        let chinShown = resting && visual?.leading == nil && meter == nil && compact != nil && shape == .chin
        let extra = resting ? trayExtra : 0
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
            pullIcon: extra > 0 && pushed == 0 ? compact?.icon : nil, pullExtra: extra, pullProgress: min(1, extra / 50),
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
            guard let self, generation == self.settleGeneration, (self.pulled == 0 && self.pushed == 0) || !animated else { return }
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
            let sessionFace: NotchSessionEar.Face? = {
                guard item.kind == .session, !item.isStale, let phase = item.sessionPhase else { return nil }
                return NotchSessionEar.face(phase: phase, sessionCount: item.sessionCount ?? 1, projectName: item.title,
                                            room: sessionRoom, measure: NotchCompactView.textWidth)
            }()
            return Compact(pid: compact?.pid, icon: compact?.icon, count: compact?.count ?? 0, changed: false,
                           leading: item.title,
                           leadingSymbol: focus ? nil : (item.symbol.isEmpty ? "circle.fill" : item.symbol),
                           trailing: Self.earTrailing(item),
                           progress: item.isStale ? nil : (focus ? (item.progress.fractionValue ?? 0) : nil),
                           quantity: focus || item.isStale ? .unknown : item.progress,
                           progressTone: tone, progressStyle: focus ? .ring : .bar, dotTone: NotchInfoDot.tone(for: item),
                           // 过期的不转圈、不猜：右耳只剩“—”。
                           sessionPhase: item.isStale ? nil : item.sessionPhase, sessionFace: sessionFace,
                           sessionSpoken: item.kind == .session && item.sessionPhase == .waiting && item.subtitle == NotchSessionEar.waitingInTerminal
                               ? NotchSessionEar.waitingInTerminal : nil,
                           music: music, calendar: item.calendar, stale: item.isStale)
        }
        return compact
    }

    /// 两边菜单栏量到的空位的小者；没量到是 nil。
    private var sessionRoom: CGFloat? {
        guard let leading = room?.leading, let trailing = room?.trailing else { return nil }
        return min(leading, trailing)
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
            if pushed >= NotchPushUp.commitTravel, pushIsTuck?() == true {
                return WSL10n.text("notch.push.hint", zh: "松手全部收进刘海")
            }
            if pulled > 0, compact == nil { return WSL10n.text("silent.launcher.open", zh: "启动台") }
            return isExpanded && tiles.isEmpty && (cardItems.isEmpty || mergedRow)
                ? WSL10n.text("notch.launchpad.hint", zh: "点一下回主屏幕 · 左右滑换 App") : nil
        }
    }
}
