// // 画布与最小形：岛的弹簧变形、遮罩裁切、内容进场时钟代理。

import Cocoa
import ApplicationServices

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
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    var onTileAccessory: ((CGWindowID) -> Void)?
    /// 两指在刘海上往下拉：拉了多少（点，往下为正）、手指是不是还在上面、此刻速度（点/秒）。
    var onPull: ((CGFloat, Bool, CGFloat) -> Void)?
    var onNavigation: ((LaunchpadController.Destination) -> Void)?
    /// 两指（或鼠标）在刘海上往上推：推了多少（点，向上为正）、手指是不是还在上面。
    var onPush: ((CGFloat, Bool) -> Void)?
    /// 往上推是不是“全部收进刘海”：是就按 NotchPushUp 的门槛（90 点 + 松手速度）；不是（主屏幕开着）沿用老的 60 点返回。
    var pushIsTuck: (() -> Bool)?
    private var pushSamples: [(TimeInterval, CGFloat)] = []
    var onActivitySelect: ((String) -> Void)?
    var onActivityAction: ((NotchActivityAction) -> Void)?
    var canSwipeActivities: (() -> Bool)?
    var onLongPress: (() -> Void)?
    var onAuxiliaryClick: ((NSEvent) -> Void)?
    var onSmartExpand: (() -> Void)?
    /// 两指在刘海上张开（拍板 10-29 第 16 条：张 = 变大）。
    var onSpread: (() -> Void)?
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
    func tileScreenRect(_ id: CGWindowID) -> NSRect? { current?.tileScreenRect(id) }
    /// 提醒里的图标在屏幕上的位置（点提醒时窗口从这里起飞）。
    var alertIconScreenRect: NSRect? { current?.alertIconScreenRect }
    private var authenticationView: (NSView & NotchInteractiveContent)?
    /// 正在缩回琥珀点的卡：画布替它留着视图，播完才拿掉。新卡或新页面来了就接着它的位置和速度（或直接拿掉）。
    private var retreatingView: (NSView & SessionCardRetreating)?
    func setAuthentication(_ view: (NSView & NotchInteractiveContent)?, retreating: Bool = false) {
        let old = authenticationView
        let inFlight = retreatingView
        authenticationView = view
        if let inFlight, inFlight !== old {
            // 上一次缩回还没播完：新卡接着它此刻的状态；不是卡就直接拿掉。
            if let snapshot = inFlight.retreatSnapshot(), let card = view as? SessionCardRetreating { card.adoptRetreat(snapshot) }
            inFlight.removeFromSuperview(); retreatingView = nil
        }
        if let old, retreating, view == nil, let card = old as? (NSView & SessionCardRetreating), card.retreatsOnRemoval {
            retreatingView = card
            card.beginRetreat { [weak self, weak card] in
                guard let self, let card, self.retreatingView === card else { return }
                card.removeFromSuperview(); self.retreatingView = nil
            }
        } else if old !== view {
            old?.removeFromSuperview()
        }
        if let view {
            if view.superview == nil { clipHost.addSubview(view) }
        }
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
            // 被取消时仍等一拍（Motion.Fade.gap）再执行新 morph：收回启动那一拍的 0.14 秒
            // 退场缓冲不该被同 tick 的 setCompact→morph 吞掉，否则形状与内容同帧突变。
            let generation = exitGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.Fade.gap) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.contentExitGeneration == generation else { return }
                    self.performMorph(to: rect, style: style, content: content, spring: spring,
                                      shoulders: scale, shoulderSnap: snap,
                                      shoulderFade: shoulderFade, done: done)
                }
            }
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
        // 弹簧飞行保护（S5 打断规则）：没弹簧可挂（正在播放 tick 的 apply 等）但岛正在飞、
        // 目标和呈现层有可见偏差时，不杀在飞动画、不直设 frame——让那根弹簧自然到达终点。
        // 岛的模型值已被上一根弹簧的 target 设对（在飞的终点就是本次的目标），视觉不会错。
        let inFlight = island.animation(forKey: "morph.bounds.size.width") != nil
            || island.animation(forKey: "morph.position.x") != nil
        let preserving = motion == nil && inFlight
            && (abs(presented.width - rect.width) > 0.5 || abs(presented.height - rect.height) > 0.5
                || abs(presented.midX - rect.midX) > 0.5)
        let shape = motion.map { handoffAxes(to: (rect, style.cornerRadius), presented: presented,
                                             presentedRadius: presentedRadius, spring: $0, now: now) }
        if !preserving {
            stripMorph(island)
            stripMorph(clip)
            stripMorph(keyLine)
            stripMorph(keyMask)
        }
        let corners: CACornerMask = style.allCorners
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let keyFrame = CGRect(x: 0, y: 0, width: rect.width, height: rect.height + (style.allCorners ? 0 : 2))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(done)
        island.maskedCorners = corners
        if !preserving {
            island.frame = rect
        }
        island.cornerRadius = style.cornerRadius
        island.backgroundColor = style.fill.cgColor
        clip.maskedCorners = corners
        if !preserving {
            clip.frame = rect
        }
        clip.cornerRadius = style.cornerRadius
        keyLine.maskedCorners = corners
        if !preserving {
            keyLine.frame = keyFrame
        }
        keyLine.cornerRadius = style.cornerRadius
        keyLine.borderWidth = style.border
        keyLine.borderColor = style.borderColor.cgColor
        // 渐变描边：只画两侧和底边，顶边不画；四角全圆的胶囊整圈照旧。
        if style.allCorners || style.border <= 0 {
            keyLine.mask = nil
        } else {
            if !preserving {
                keyMask.frame = CGRect(origin: .zero, size: keyFrame.size)
            }
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
                view.onSelect = { [weak self] id in self?.onMinimumTap?(id) }
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

    /// 第二颗岛位移与尺寸动画的键：`add(_:key:to:shape:now:)` 按「前缀.keyPath」逐轴挂，这里与它保持一致。
    private static let companionMotionKeys = ["companion.position.x", "companion.position.y",
                                              "companion.bounds.size.width", "companion.bounds.size.height"]

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
        if let current, let shown, shown.same(as: content) {
            current.place(in: rect, content: content)
            self.shown = content
            return  // 同层原地更新：看门狗继续盯（新内容可能在等形状走到四成才淡入），不杀它
        }
        stopContentWatch()
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
        // 有格子进出（回到原处后其余格子补位）时整排重建：滚动位置带过来，看得见的格子不跳。
        if let outgoing = current { incoming.carryRowOffset(outgoing.rowOffset) }
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
        let inflight = Self.companionMotionKeys.contains { companion.animation(forKey: $0) != nil }
        if inflight { companionRetargeted = true }
        companion.isHidden = false
        companion.cornerRadius = height / 2
        if let text { companionLabel.string = text }
        companionLabel.frame = CGRect(x: 12, y: (height - 16) / 2, width: width - 24, height: 16)
        let fromOpacity = companion.presentation()?.opacity ?? companion.opacity
        let toOpacity: Float = text == nil ? 0 : 1
        if reduced {
            for key in Self.companionMotionKeys { companion.removeAnimation(forKey: key) }
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
        let moving = Self.companionMotionKeys.contains { companion.animation(forKey: $0) != nil }
        let fading = companion.animation(forKey: "companion.opacity") != nil
        return (Motion.reduced ? showing : apart && showing, companionRetargeted, !moving && (fading || Motion.reduced))
    }

    /// 落定：旧的一层都撤掉。
    func settle() {
        for view in clipHost.subviews where view !== current && view !== authenticationView && view !== retreatingView { view.removeFromSuperview() }
        // 淡入被中途打断（alpha 还在 0 到 1 之间）时直接拍亮会闪一下；
        // 只在完全不可见（alpha < 0.01）或已可见时才设。
        if let current, current.alphaValue < 0.01 || current.alphaValue >= 0.99 {
            current.alphaValue = 1
        }
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
        if minimumView(at: event) != nil { hoverHeldByMinimum = true; return }
        hoverHeldByMinimum = false
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        hoverHeldByMinimum = false
        holdTimer?.invalidate(); holdTimer = nil; if mouseDragAxis == nil { pressedAt = nil }; onHover?(false)
    }
    override func mouseMoved(with event: NSEvent) {
        if hoverHeldByMinimum, minimumView(at: event) == nil { hoverHeldByMinimum = false; onHover?(true); return }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 点刘海（不在某一格上）：按下时岛就鼓一下（点几下鼓多大），松开才算；按下后拖开了不算。
    var onPress: ((Int) -> Void)?
    /// 点在某件活动的紧凑左耳或右耳上（一下）：参数是紧凑那件是不是正在播放。没接上（nil）= 照原来的 onPress(1)。
    var onEarTap: ((Bool) -> Void)?
    /// 点在最小形（小圆）上：参数是那件活动的 id。
    var onMinimumTap: ((String) -> Void)?
    private var pressedAt: NSPoint?
    /// 这一次触控板手势归不归那一排（nil：还没定）。
    private var rowScrollOwner: Bool?
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
            holdTimer = Timer.scheduledTimer(withTimeInterval: Motion.Hold.longPress, repeats: false) { [weak self] _ in
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
            } else if distance.y < 0, pushIsTuck?() == true {
                finishPush(travelUp: -distance.y, samples: mouseDragSamples.map { ($0.0, -$0.1.y) })
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
        // 照系统的岛，按点的位置分三块：左耳、右耳打开那件活动；刘海本体照旧回到主屏幕（下面的 onPress）。
        if event.clickCount == 1, let current, shown?.tiles.isEmpty == true, shown?.activitiesExpanded != true,
           current.isOnActivityEar(windowPoint: event.locationInWindow), let onEarTap {
            onEarTap(current.compactIsMusic)
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
        else { onPull?(max(0, distance.y), true, 0); onPush?(max(0, -distance.y), true) }
    }

    /// 往上推松手：推过 90 点、而且按松手时的速度推算还能走到 120 点才收，不然岛弹回去（NotchPushUp）。
    private func finishPush(travelUp: CGFloat, samples: [(TimeInterval, CGFloat)]) {
        var velocity: CGFloat = 0
        if let first = samples.first, let last = samples.last, last.0 - first.0 > 0.005 {
            velocity = (last.1 - first.1) / CGFloat(last.0 - first.0)
        }
        onPush?(0, false)
        onPull?(0, false, 0)
        if NotchPushUp.commits(travel: travelUp, velocity: velocity) { onNavigation?(.back) }
    }
    func cancelHold() { holdTimer?.invalidate(); holdTimer = nil; pressedAt = nil; mouseDragAxis = nil }
    func resetInteractions() {
        cancelHold(); fileDwell?.invalidate(); fileDwell = nil
        _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
        pull = nil; horizontal = nil; travel = .zero; horizontalSamples = []; pushSamples = []
        onPush?(0, false)
    }
    override func cancelOperation(_ sender: Any?) {
        if let authenticationView { authenticationView.onCancel?(); return }
        cancelHold()
        _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
        onPush?(0, false)
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
        if routeRowScroll(event) { return }
        guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return }
        let fingerDown = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        let fingerRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        switch event.phase {
        case .began, .mayBegin:
            travel = .zero; horizontal = nil; horizontalSamples = [(event.timestamp, 0)]
            pull = (0, [(event.timestamp, 0)]); pushSamples = [(event.timestamp, 0)]
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
            pushSamples.append((event.timestamp, -travel.y)); pushSamples = Array(pushSamples.suffix(6))
            onPush?(max(0, -travel.y), true)
            onPull?(current.distance, true, 0)
        case .ended, .cancelled:
            guard let current = pull else { return }
            pull = nil
            // 取消必须回弹，不能拿累计位移当作一次成功的松手。
            if event.phase == .cancelled {
                _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
                onPush?(0, false)
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
            } else if travel.y < 0, pushIsTuck?() == true {
                finishPush(travelUp: -travel.y, samples: pushSamples)
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

    /// 那一排放不下时，指针在那一排上的横扫（触控板双指、滚轮、惯性）滚那一排，不当作切活动、翻页，也不收起那一排。
    /// 触控板一次手势在开头就定好归谁（横向为主才归那一排），惯性接着同一个主人；普通滚轮没有横向分量，竖滚也横着滚。
    private func routeRowScroll(_ event: NSEvent) -> Bool {
        guard let current, current.rowCanScroll, current.rowScrollArea(contains: event.locationInWindow) else {
            if event.phase == .began || event.phase == .mayBegin { rowScrollOwner = nil }
            return false
        }
        let precise = event.hasPreciseScrollingDeltas
        let dx = Double(event.scrollingDeltaX), dy = Double(event.scrollingDeltaY)
        if precise, event.phase != [] || event.momentumPhase != [] {
            if event.phase == .began || event.phase == .mayBegin { rowScrollOwner = nil }
            if event.momentumPhase == .began { rowScrollOwner = rowScrollOwner ?? false }
            if rowScrollOwner == nil, dx != 0 || dy != 0 { rowScrollOwner = NotchRow.scrollBelongsToRow(precise: true, deltaX: dx, deltaY: dy) }
            let owned = rowScrollOwner == true
            if owned { current.scrollRow(by: NotchRow.scrollDelta(precise: true, deltaX: dx, deltaY: dy)) }
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled || event.phase == .cancelled { rowScrollOwner = nil }
            // 手指抬起且没有惯性时（.ended 后不再有 momentum 事件）下一次手势会从 .began 重新定主人。
            return owned
        }
        // 普通滚轮、没有相位的平滑滚轮。
        guard NotchRow.scrollBelongsToRow(precise: precise, deltaX: dx, deltaY: dy) else { return false }
        current.scrollRow(by: NotchRow.scrollDelta(precise: precise, deltaX: dx, deltaY: dy))
        return true
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
            else if pinchAmount > 0.18 { onSpread?() }
            pinchAmount = 0
        }
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
