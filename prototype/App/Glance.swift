// 看一眼：指针停在卷帘条上，那扇窗的画面出现；移开就收回；单击画面才真正打开它。
//
// 两种卷帘条都能看一眼：
// - 收起的窗口：画面贴在卷帘条下沿，按原尺寸出现在原处。
// - 带到每张桌面的窗口（见 Carry.swift）：窗口留在自己的桌面，画面挂在别的桌面
//   右上角那条卷帘条下面，按比例缩小。
//
// 真窗口不激活、不移动。画面有三种来源：
// - 直接开流：真窗口挪在屏幕外，或在别的桌面上照常显示。指针一进卷帘条就开流，
//   停够时间再显示，多数时候显示那一刻第一帧已经到了。
// - 盖住再取消隐藏：整个 App 被隐藏时，画面先卷下来盖住原处，再在下面临时取消
//   隐藏、开流；收回时先藏回去再卷上。
// - 只有截图：最小化、没有屏幕录制权限等，右下角照实标明不是实时画面。

import AVFoundation
import Cocoa
import ScreenCaptureKit

let glanceEnabledDefaultsKey = "GlanceEnabled"

/// 一条能看一眼的卷帘条背后是什么，以及画面该放在哪。
struct GlanceTarget {
    enum Source { case stream, unhideUnderCover, snapshotOnly }

    /// 卷帘条的位置（屏幕坐标）。
    let strip: NSRect
    /// 画面面板的位置（屏幕坐标），含卡片四周给投影留的边距。
    let panel: NSRect
    /// 卡片在面板里的位置（非翻转坐标）。
    let card: NSRect
    /// 整扇窗口的画面在卡片里的位置，超出卡片的部分（标题栏、屏幕外）裁掉。
    let picture: NSRect
    /// 真窗口会在底下临时取消隐藏时，它露在卡片之外的那块区域（屏幕坐标）：
    /// 打开时截一张那里原本的背景垫上。
    let backdropArea: NSRect?
    /// 画面四个角的圆角半径（点），取真窗口自己的。
    let cornerRadius: CGFloat
    let source: Source
    let snapshot: CGImage?
    let pid: pid_t
    let bundleID: String
    let accessibilityTitle: String
    /// 画面不是实时的时候，右下角写什么。
    let staleText: String
}

/// 带到每张桌面的窗口：由 CarryController 提供。
@MainActor
protocol GlanceCarrySource: AnyObject {
    func carriedStripFrame(_ id: CGWindowID) -> NSRect?
    func glanceTarget(forCarried id: CGWindowID) -> GlanceTarget?
    func openCarriedWindow(_ id: CGWindowID)
}

/// 探针与日志读的数字：从指针决定打开到画面出现、到第一帧实时画面各用了多久。
struct GlanceDiagnostics {
    var opens = 0
    var closes = 0
    var discards = 0
    var lastID: CGWindowID = 0
    var lastLiveExpected = false
    var lastPreparedAt: TimeInterval?
    var lastOpenRequestedAt: TimeInterval?
    var lastShownAt: TimeInterval?
    var lastFirstFrameAt: TimeInterval?
    var lastPanelFrame: NSRect = .zero
    var lastShowedStaleNotice = false
}

private final class GlanceHoverRelay: NSResponder {
    let id: CGWindowID
    weak var controller: GlanceController?
    weak var view: NSView?
    var area: NSTrackingArea?

    init(id: CGWindowID, controller: GlanceController) {
        self.id = id
        self.controller = controller
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) {
        controller?.pointerEntered(id)
    }

    override func mouseExited(with event: NSEvent) {
        controller?.pointerExited(id)
    }

    func uninstall() {
        if let area { view?.removeTrackingArea(area) }
        area = nil
    }
}

private final class GlanceSession {
    enum Stage { case preparing, waitingForFrame, shown, closing, expanding }

    let id: CGWindowID
    let preparedAt: TimeInterval
    let stripFrame: NSRect
    let liveExpected: Bool
    let carried: Bool
    var stage: Stage = .preparing
    var capture: WindowStreamCapture?
    var startupTask: Task<Void, Never>?
    var captureFailed = false
    var cancelled = false
    var panel: GlancePanel?
    var content: GlanceContentView?
    var openRequestedAt: TimeInterval?
    var showDeadline: TimeInterval?
    var shownAt: TimeInterval?
    var firstFrameAt: TimeInterval?
    /// 被整体隐藏的 App：画面盖好之后在原处取消隐藏，拿到实时画面；收回时先藏回去再卷上。
    var viaUnhide = false
    var pid: pid_t = 0
    var bundleID = ""
    var unhideAt: TimeInterval?
    var unhiddenAt: TimeInterval?
    var frontmostBeforeUnhide: pid_t?
    var rehiddenAt: TimeInterval?
    /// 卡片在屏幕上的位置：“指针在画面上”只看卡片，不算投影边距。
    var cardScreen: NSRect?
    var hasBackdrop = false

    init(id: CGWindowID, preparedAt: TimeInterval, stripFrame: NSRect, liveExpected: Bool,
         carried: Bool) {
        self.id = id
        self.preparedAt = preparedAt
        self.stripFrame = stripFrame
        self.liveExpected = liveExpected
        self.carried = carried
    }

    var hasLiveFrame: Bool { firstFrameAt != nil }

    func tearDown() {
        cancelled = true
        startupTask?.cancel()
        startupTask = nil
        capture?.stop()
        capture = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        content = nil
    }
}

@MainActor
final class GlanceController {
    /// 实时画面最多等这么久；等不到就先给截图。
    static let firstFrameWait: TimeInterval = 0.25
    /// 显示后仍没有实时画面，就标明这不是实时画面。
    static let staleNoticeDelay: TimeInterval = 0.5

    /// 被整体隐藏的 App 在画面下面临时取消隐藏以拿到实时画面。
    /// 实测（macOS 27.0）：辅助功能取消隐藏 23ms 回到原处、前台不变；首帧 104ms；藏回 13ms。
    nonisolated(unsafe) static var unhideForLiveEnabled = true
    /// 取消隐藏后出现前台切换的 App：不再对它这样做。
    private var activatesOnUnhide: Set<String> = []
    /// 这段时间内“App 又显示出来”是看一眼自己造成的，不当作用户唤回。
    private var revealHoldUntil: [CGWindowID: TimeInterval] = [:]

    /// 探针不改用户的偏好设置，只在本进程里强制打开。
    nonisolated(unsafe) static var probeOverride: Bool?

    nonisolated static var isEnabled: Bool {
        get {
            if let probeOverride { return probeOverride }
            let defaults = UserDefaults.standard
            return defaults.object(forKey: glanceEnabledDefaultsKey) == nil
                ? true : defaults.bool(forKey: glanceEnabledDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: glanceEnabledDefaultsKey) }
    }

    unowned let owner: AppDelegate
    weak var carrySource: GlanceCarrySource?
    let intent = GlanceIntent()
    /// 探针替换这两个入口来模拟指针与时钟；平时读真实的指针位置。
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// 探针的临时窗口可能被别的窗口挡住：只按几何判断指针在哪。
    var hitTestsByGeometry = false
    private(set) var diagnostics = GlanceDiagnostics()

    private var relays: [CGWindowID: GlanceHoverRelay] = [:]
    private var cornerRadii: [CGWindowID: CGFloat] = [:]
    private var sessions: [CGWindowID: GlanceSession] = [:]
    private var timer: DispatchSourceTimer?
    private var timerIsFast = false

    init(owner: AppDelegate) {
        self.owner = owner
    }

    // MARK: 卷帘条进出

    /// 卷帘条装好后调用：挂上悬停跟踪。收起那一下指针还停在上面，先挡住这一条。
    func attach(id: CGWindowID, overlay: NSWindow) {
        relays.removeValue(forKey: id)?.uninstall()
        guard let view = overlay.contentView else { return }
        let relay = GlanceHoverRelay(id: id, controller: self)
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: relay, userInfo: nil)
        view.addTrackingArea(area)
        relay.view = view
        relay.area = area
        relays[id] = relay
        if overlay.isVisible, overlay.frame.insetBy(dx: -2, dy: -2).contains(pointerLocation()) {
            intent.block(id)
            ensureTimer()
        }
    }

    /// 卷帘条没了（展开、清理、不再带着）：它的看一眼立刻撤掉，不播卷上。
    func detach(id: CGWindowID) {
        relays.removeValue(forKey: id)?.uninstall()
        cornerRadii.removeValue(forKey: id)
        let effects = intent.forget(id)
        if let session = sessions[id], session.stage != .expanding {
            finish(session, reason: "detached")
        }
        apply(effects.filter { $0 != .close(id) && $0 != .discard(id) })
    }

    func pointerEntered(_ id: CGWindowID) {
        guard Self.isEnabled, stripFrame(id) != nil,
              !owner.hoverPreviewIsSuppressed(id) else { return }
        apply(intent.entered(id, at: clock()))
    }

    func pointerExited(_ id: CGWindowID) {
        intent.unblock(id)
    }

    /// 单击卷帘条：不等计时，马上看。
    func stripClicked(_ id: CGWindowID) {
        guard Self.isEnabled, stripFrame(id) != nil else { return }
        apply(intent.clicked(id, at: clock()))
    }

    /// 更多窗口菜单关闭后，给指针从菜单移到预览的时间；不激活源窗口。
    func previewFromMenu(_ id: CGWindowID) {
        guard Self.isEnabled, stripFrame(id) != nil else { return }
        apply(intent.menuSelected(id, at: clock()))
    }

    /// 切换 App、换桌面、关掉设置：收回正在看的那一个。
    func cancelAll(reason: String) {
        let effects = intent.cancel()
        if !effects.isEmpty { wlog("glance: cancel reason=\(reason)") }
        apply(effects)
    }

    /// 用户切回临时取消隐藏的 App：先交出隐藏所有权，再走正常展开，不能把它藏回去。
    func takeOverUnhiddenSessions(for pid: pid_t, restore: (CGWindowID) -> Void) {
        for session in Array(sessions.values) where session.pid == pid
            && session.viaUnhide && session.frontmostBeforeUnhide != nil
            && session.stage != .expanding {
            session.stage = .expanding
            _ = intent.forget(session.id)
            revealHoldUntil.removeValue(forKey: session.id)
            finish(session, reason: "user-activated-source")
            restore(session.id)
        }
        ensureTimer()
    }

    func hasSession(_ id: CGWindowID) -> Bool { sessions[id] != nil }

    /// “App 又显示出来 / 窗口在屏幕上”是不是看一眼自己造成的。
    func holdsReveal(_ id: CGWindowID) -> Bool {
        if let session = sessions[id], session.viaUnhide, session.unhideAt != nil,
           session.stage != .expanding {
            return true
        }
        guard let until = revealHoldUntil[id] else { return false }
        if clock() < until { return true }
        revealHoldUntil.removeValue(forKey: id)
        return false
    }

    var isShowing: Bool {
        sessions.values.contains { $0.stage == .shown || $0.stage == .waitingForFrame }
    }

    func panelFrame(for id: CGWindowID) -> NSRect? {
        sessions[id]?.panel?.frame
    }

    /// 卡片在屏幕上的位置。
    func cardFrame(for id: CGWindowID) -> NSRect? {
        sessions[id]?.cardScreen
    }

    func hasBackdrop(_ id: CGWindowID) -> Bool {
        sessions[id]?.hasBackdrop == true
    }

    /// 实时画面真的显示在看一眼里：收到了带像素的帧，而且视频层挂在画面上。
    func isLive(_ id: CGWindowID) -> Bool {
        guard let session = sessions[id] else { return false }
        return session.hasLiveFrame && session.content?.showsVideo == true
    }

    func pixelFrames(_ id: CGWindowID) -> UInt64 {
        sessions[id]?.capture?.pixelFrameCount ?? 0
    }

    // MARK: 目标

    private func stripFrame(_ id: CGWindowID) -> NSRect? {
        if let overlay = owner.shaded[id]?.overlay { return overlay.frame }
        return carrySource?.carriedStripFrame(id)
    }

    private func target(for id: CGWindowID) -> GlanceTarget? {
        if let state = owner.shaded[id] {
            guard let overlay = state.overlay else { return nil }
            return shadedTarget(state: state, strip: overlay.frame)
        }
        return carrySource?.glanceTarget(forCarried: id)
    }

    /// 卡片和卷帘条之间的缝（点）。
    static let cardGap: CGFloat = 6

    /// 收起的窗口：原貌卷帘条不动，卡片挂在它下面、隔一道缝，按原尺寸显示标题栏以下的
    /// 内容；超出屏幕可见区域的部分裁掉，上沿不动。
    private func shadedTarget(state: ShadeState, strip: NSRect) -> GlanceTarget? {
        let size = state.originalSize
        let barH = min(strip.height, max(0, size.height - 40))
        let contentH = size.height - barH
        let wanted = NSRect(x: strip.minX, y: strip.minY - Self.cardGap - contentH,
                            width: size.width, height: contentH)
        let card = wanted.intersection(owner.visibleFrame(for: strip))
        guard !card.isNull, card.width >= 80, card.height >= 40,
              abs(card.maxY - wanted.maxY) < 0.5 else { return nil }
        let clippedLeft = card.minX - wanted.minX
        let margin = GlanceContentView.shadowMargin
        var panel = NSRect(x: card.minX - margin, y: card.minY - margin,
                           width: card.width + 2 * margin, height: strip.minY - (card.minY - margin))
        if let screen = screenForCocoaFrame(strip)?.frame { panel = panel.intersection(screen) }
        let picture = NSRect(x: -clippedLeft, y: card.height + barH - size.height,
                             width: size.width, height: size.height)
        let snapshot = state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let canRecord = hasScreenRecordingPermission()
        let source: GlanceTarget.Source
        // 真窗口临时回来时，卷帘条下面那块（标题栏以下）就是它的内容区：缝和卡片的圆角缺口
        // 都落在这里，要垫背景。
        let realContent = NSRect(x: strip.minX, y: strip.minY - contentH,
                                 width: size.width, height: contentH)
        var backdropArea: NSRect?
        if (state.hide == .offscreen || state.hide == .privateOffscreen) && canRecord {
            source = .stream
        } else if canRecord, canUnhideUnderCover(state: state, strip: strip, card: card,
                                                   wanted: wanted, panel: panel,
                                                   realContent: realContent) {
            source = .unhideUnderCover
            backdropArea = realContent
        } else {
            source = .snapshotOnly
        }
        return GlanceTarget(
            strip: strip, panel: panel, card: card.offsetBy(dx: -panel.minX, dy: -panel.minY),
            picture: picture, backdropArea: backdropArea,
            cornerRadius: windowCornerRadius(state.sourceWindowID, snapshot: snapshot,
                                             windowWidth: size.width),
            source: source,
            snapshot: snapshot,
            pid: state.pid, bundleID: state.bundleID,
            accessibilityTitle: descriptiveDisplayTitle(appName: state.appName, windowTitle: state.title),
            staleText: "收起时的画面")
    }

    /// 真窗口临时回到原处时，必须被卷帘条（标题栏）和面板（卡片 + 背景垫片）完全盖住。
    private func canUnhideUnderCover(state: ShadeState, strip: NSRect, card: NSRect,
                                     wanted: NSRect, panel: NSRect, realContent: NSRect) -> Bool {
        guard Self.unhideForLiveEnabled, state.hide == .hidden, FastCapture.isAvailable,
              !activatesOnUnhide.contains(state.bundleID) else { return false }
        let original = cocoaFrame(fromAXPosition: state.originalPosition, size: state.originalSize)
        let stripAtOrigin = abs(strip.minX - original.minX) < 1 && abs(strip.maxY - original.maxY) < 1
            && strip.width >= original.width - 1
        let cardWhole = framesAlmostEqual(card, wanted, tolerance: 0.5)
        return stripAtOrigin && cardWhole && panel.insetBy(dx: -0.5, dy: -0.5).contains(realContent)
    }

    // MARK: 效果

    private func apply(_ effects: [GlanceEffect]) {
        for effect in effects {
            switch effect {
            case .prewarm(let id): prepare(id)
            case .discard(let id): discard(id)
            case .open(let id): open(id)
            case .close(let id): close(id)
            }
        }
        ensureTimer()
    }

    private func prepare(_ id: CGWindowID) {
        if let existing = sessions[id] {
            if existing.stage == .closing, existing.rehiddenAt != nil {
                // 真窗口已藏回、视频流已停：旧画面不能再当作实时会话复用。
                finish(existing, reason: "reenter-after-rehide")
            } else {
                if existing.stage == .closing {
                    // 卷上途中指针回来了：接着用同一路画面。
                    existing.content?.cancelRollUp()
                    existing.stage = .shown
                }
                return
            }
        }
        guard let target = target(for: id) else { return }
        let session = GlanceSession(id: id, preparedAt: clock(), stripFrame: target.strip,
                                    liveExpected: target.source != .snapshotOnly,
                                    carried: owner.shaded[id] == nil)
        session.viaUnhide = target.source == .unhideUnderCover
        session.pid = target.pid
        session.bundleID = target.bundleID
        sessions[id] = session
        // 能直接开流的现在就开；被隐藏的要等画面盖好、取消隐藏之后。
        if target.source == .stream { startCapture(session) }
    }

    private func startCapture(_ session: GlanceSession) {
        let id = session.id
        let capture = WindowStreamCapture()
        session.capture = capture
        // 画面可能已经建好（被隐藏的 App 要等盖住之后才开流）：视频层现在就挂上去。
        session.content?.attachVideo(capture.videoLayer)
        let stripScreen = screenForCocoaFrame(session.stripFrame)
        let wantedDisplay = stripScreen.flatMap { displayID(for: $0) }
        session.startupTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session, !session.cancelled else { return }
            guard let content = await ShareableContentCache.shared.content(requiring: id),
                  let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                session.captureFailed = true
                wlog("glance: no capturable window id=\(id)")
                return
            }
            guard !session.cancelled else { return }
            let display = content.displays.first { $0.displayID == wantedDisplay }
            do {
                try await capture.start(window: scWindow, display: display)
            } catch {
                session.captureFailed = true
                wlog("glance: capture failed id=\(id) \(error.localizedDescription)")
                return
            }
            guard !session.cancelled, self.sessions[id] === session else {
                capture.stop()
                return
            }
            capture.isInteractive = true
        }
    }

    private func discard(_ id: CGWindowID) {
        guard let session = sessions[id] else { return }
        switch session.stage {
        case .preparing:
            diagnostics.discards += 1
            finish(session, reason: "discard")
        case .shown:
            // 卷上途中被指针拉回来、随后又没停够就离开：照常收回。
            close(id)
        case .waitingForFrame, .closing, .expanding:
            break
        }
    }

    private func open(_ id: CGWindowID) {
        guard let session = sessions[id] else { return }
        if session.stage == .shown || session.stage == .waitingForFrame { return }
        guard let target = target(for: id) else {
            // 卷帘条还在，但背后的窗口不再能看一眼：忘掉这条卷帘条的意图，
            // 立刻收掉已经开始准备的会话，别留下没人管的准备。
            wlog("glance: no room id=\(id)")
            _ = intent.forget(id)
            finish(session, reason: "no-room")
            return
        }
        let now = clock()
        session.openRequestedAt = now
        let panel = GlancePanel(frame: target.panel)
        let content = GlanceContentView(
            frame: NSRect(origin: .zero, size: target.panel.size),
            cardFrame: target.card, pictureFrame: target.picture,
            cornerRadius: target.cornerRadius,
            staleText: target.staleText, accessibilityTitle: target.accessibilityTitle)
        session.cardScreen = target.card.offsetBy(dx: target.panel.minX, dy: target.panel.minY)
        if session.viaUnhide {
            // 真窗口还藏着：此刻那块区域的样子就是它背后的背景。截不到就不取消隐藏，只给截图。
            if let area = target.backdropArea,
               let backdrop = FastCapture.composite(
                excluding: [], rect: CGRect(origin: axPosition(fromCocoaFrame: area), size: area.size)) {
                content.setBackdrop(backdrop, frame: area.offsetBy(dx: -target.panel.minX,
                                                                   dy: -target.panel.minY))
                session.hasBackdrop = true
            } else {
                session.viaUnhide = false
                session.captureFailed = true
                wlog("glance: no backdrop id=\(id); snapshot only")
            }
        }
        content.setSnapshot(target.snapshot)
        if let capture = session.capture { content.attachVideo(capture.videoLayer) }
        content.onClick = { [weak self] in self?.expand(id) }
        panel.contentView = content
        session.panel = panel
        session.content = content
        diagnostics.lastPanelFrame = target.panel
        refreshLiveState(session, now: now)
        if session.viaUnhide {
            show(session, now: now)
            let rollDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.18
            session.unhideAt = now + rollDuration + 0.02
        } else if session.liveExpected, !session.hasLiveFrame, !session.captureFailed {
            session.stage = .waitingForFrame
            session.showDeadline = now + Self.firstFrameWait
        } else {
            show(session, now: now)
        }
    }

    private func show(_ session: GlanceSession, now: TimeInterval) {
        guard let panel = session.panel, let content = session.content else { return }
        session.stage = .shown
        session.shownAt = now
        content.setLive(session.hasLiveFrame)
        content.setStaleNoticeVisible(!session.liveExpected || session.captureFailed)
        panel.orderFrontRegardless()
        content.rollDown()
        diagnostics.opens += 1
        diagnostics.lastID = session.id
        diagnostics.lastLiveExpected = session.liveExpected
        diagnostics.lastPreparedAt = session.preparedAt
        diagnostics.lastOpenRequestedAt = session.openRequestedAt
        diagnostics.lastShownAt = now
        diagnostics.lastFirstFrameAt = session.firstFrameAt
        diagnostics.lastShowedStaleNotice = !session.liveExpected || session.captureFailed
        let prepared = Int((now - session.preparedAt) * 1000)
        let asked = Int((now - (session.openRequestedAt ?? now)) * 1000)
        wlog("glance: show id=\(session.id) carried=\(session.carried) live=\(session.hasLiveFrame) expected=\(session.liveExpected) sincePointer=\(prepared)ms sinceIntent=\(asked)ms")
    }

    private func close(_ id: CGWindowID) {
        guard let session = sessions[id] else { return }
        switch session.stage {
        case .expanding, .closing:
            return
        case .preparing, .waitingForFrame:
            finish(session, reason: "close-before-show")
        case .shown:
            session.stage = .closing
            diagnostics.closes += 1
            guard let content = session.content else {
                finish(session, reason: "close")
                return
            }
            if session.viaUnhide, session.unhideAt != nil, rehide(session) {
                // 先把真窗口藏回去，确认它离开屏幕再卷上画面，免得卷上时露出真窗口。
                return
            }
            content.rollUp { [weak self, weak session] in
                guard let self, let session, session.stage == .closing else { return }
                self.finish(session, reason: "close")
            }
        }
    }

    private func finish(_ session: GlanceSession, reason: String) {
        if sessions[session.id] === session {
            sessions.removeValue(forKey: session.id)
        }
        if session.viaUnhide, session.unhideAt != nil, session.stage != .expanding,
           session.rehiddenAt == nil, owner.shaded[session.id] != nil {
            _ = rehide(session)
        }
        session.tearDown()
        if reason != "discard" && reason != "close-before-show" {
            wlog("glance: end id=\(session.id) reason=\(reason)")
        }
    }

    /// 单击画面：真正打开那扇窗。收起的窗口原地展开，画面留到真窗口回到原处再撤；
    /// 带到每张桌面的窗口：回到它所在的桌面。
    func expand(_ id: CGWindowID) {
        guard let session = sessions[id] else { return }
        session.stage = .expanding
        _ = intent.forget(id)
        if session.carried {
            wlog("glance: open carried window id=\(id)")
            carrySource?.openCarriedWindow(id)
            finish(session, reason: "opened")
            return
        }
        guard owner.shaded[id] != nil else {
            finish(session, reason: "expand-gone")
            return
        }
        wlog("glance: expand id=\(id)")
        let restored = owner.unshadeReturningElement(id, onVerified: { [weak self, weak session] _ in
            guard let self, let session else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.finish(session, reason: "expanded")
            }
        })
        if restored == nil {
            finish(session, reason: "expand-failed")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self, weak session] in
            guard let self, let session else { return }
            self.finish(session, reason: "expand-timeout")
        }
    }

    // MARK: 被隐藏的 App：盖住再取消隐藏

    private func driveUnhide(_ session: GlanceSession, now: TimeInterval) {
        guard session.viaUnhide else { return }
        if session.stage == .shown, session.unhiddenAt == nil,
           let at = session.unhideAt, now >= at, session.frontmostBeforeUnhide == nil {
            session.frontmostBeforeUnhide = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
            revealHoldUntil[session.id] = now + 5
            let ok = setAXAppHidden(pid: session.pid, false)
            wlog("glance: unhide under cover id=\(session.id) pid=\(session.pid) ax=\(ok)")
            if !ok { session.captureFailed = true }
        }
        if session.frontmostBeforeUnhide != nil, session.unhiddenAt == nil,
           session.capture == nil, !session.captureFailed,
           windowIsOnScreenNow(session.id) {
            session.unhiddenAt = now
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if front == session.pid, session.frontmostBeforeUnhide != session.pid {
                // 取消隐藏把它换到了前台：这个 App 以后不再这样做。
                activatesOnUnhide.insert(session.bundleID)
                wlog("glance: unhide activated app bundle=\(session.bundleID); falling back to snapshots for it")
            }
            startCapture(session)
        }
        if session.frontmostBeforeUnhide != nil, session.unhiddenAt == nil,
           let at = session.unhideAt, now - at > 0.8, !session.captureFailed {
            session.captureFailed = true
            wlog("glance: window did not come back under cover id=\(session.id)")
        }
        if session.stage == .closing, let rehiddenAt = session.rehiddenAt,
           !windowIsOnScreenNow(session.id) || now - rehiddenAt > 0.4 {
            session.rehiddenAt = .infinity
            session.content?.rollUp { [weak self, weak session] in
                guard let self, let session, session.stage == .closing else { return }
                self.finish(session, reason: "close")
            }
        }
    }

    /// 把临时取消隐藏的 App 藏回去。返回 true 表示要等它离开屏幕再卷上。
    private func rehide(_ session: GlanceSession) -> Bool {
        guard session.frontmostBeforeUnhide != nil, session.rehiddenAt == nil else { return false }
        session.capture?.stop()
        session.capture = nil
        let ok = setAXAppHidden(pid: session.pid, true)
        session.rehiddenAt = clock()
        revealHoldUntil[session.id] = clock() + 1.0
        wlog("glance: hide again id=\(session.id) ax=\(ok)")
        return ok
    }

    // MARK: 定时采样

    private var needsTimer: Bool {
        intent.needsSampling || !intent.blocked.isEmpty || !sessions.isEmpty
    }

    private func ensureTimer() {
        guard needsTimer else {
            timer?.cancel()
            timer = nil
            return
        }
        // 只在准备或显示画面时高频采样；只是等指针离开刚收起的卷帘条，每秒 4 次就够。
        let fast = intent.needsSampling || !sessions.isEmpty
        if let timer {
            if fast != timerIsFast {
                timerIsFast = fast
                timer.schedule(deadline: .now() + .milliseconds(fast ? 16 : 250),
                               repeating: .milliseconds(fast ? 33 : 250), leeway: .milliseconds(fast ? 4 : 50))
            }
            return
        }
        timerIsFast = fast
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .milliseconds(fast ? 16 : 250),
                        repeating: .milliseconds(fast ? 33 : 250), leeway: .milliseconds(fast ? 4 : 50))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = source
        source.resume()
    }

    private func tick() {
        let now = clock()
        let point = pointerLocation()
        for id in intent.blocked {
            guard let frame = stripFrame(id), frame.insetBy(dx: -2, dy: -2).contains(point) else {
                intent.unblock(id)
                continue
            }
        }
        for session in Array(sessions.values) {
            driveUnhide(session, now: now)
            refreshLiveState(session, now: now)
            if session.stage == .waitingForFrame,
               session.hasLiveFrame || session.captureFailed
                || now >= (session.showDeadline ?? now) {
                show(session, now: now)
            }
            if session.stage == .shown, session.liveExpected, !session.hasLiveFrame,
               let shownAt = session.shownAt,
               now - shownAt >= (session.viaUnhide ? 1.0 : Self.staleNoticeDelay) {
                session.content?.setStaleNoticeVisible(true)
                diagnostics.lastShowedStaleNotice = true
            }
            if session.stage != .expanding, session.stage != .closing,
               let frame = stripFrame(session.id), !framesAlmostEqual(frame, session.stripFrame) {
                // 卷帘条被拖走了：画面不跟着飘，直接收回。
                apply(intent.forget(session.id))
                if let stale = sessions[session.id], stale === session {
                    finish(session, reason: "strip-moved")
                }
            }
        }
        if intent.needsSampling {
            apply(intent.sample(sample(at: point), at: now))
        }
        ensureTimer()
    }

    private func refreshLiveState(_ session: GlanceSession, now: TimeInterval) {
        guard !session.hasLiveFrame, let capture = session.capture,
              capture.pixelFrameCount > 0 else { return }
        session.firstFrameAt = now
        diagnostics.lastFirstFrameAt = now
        session.content?.setLive(true)
    }

    /// 真窗口的圆角半径（点）：从截图左上角量第一行第一个不透明像素的位置，再按连续曲率换算。
    /// 量不出来就用系统窗口的默认圆角。同一扇窗只量一次。
    func windowCornerRadius(_ id: CGWindowID, snapshot: CGImage?, windowWidth: CGFloat) -> CGFloat {
        if let cached = cornerRadii[id] { return cached }
        guard let snapshot, windowWidth > 0,
              let corner = snapshot.cropping(to: CGRect(x: 0, y: 0, width: min(snapshot.width, 240),
                                                        height: min(snapshot.height, 240))),
              let pixels = estimatedCornerRadiusPixels(from: corner) else {
            return SystemCornerRadius.window
        }
        // 量到的是弧线从哪里开始。窗口用的是连续曲率圆角，弧线起点在半径的约 1.528 倍处，
        // 换算回半径，画面的角才和真窗口重合，不会在外面露出一圈底下的边。
        let extent = pixels / (CGFloat(snapshot.width) / windowWidth)
        let radius = min(40, max(4, extent / 1.528))
        cornerRadii[id] = radius
        return radius
    }

    /// 卷帘条两端的控件区：收起的窗口左边是红绿灯（经典条右边还有缩放与展开）；
    /// 带到每张桌面的卷帘条右边是“不再带着”。
    private func controlsZone(_ id: CGWindowID) -> (left: CGFloat, right: CGFloat) {
        if let state = owner.shaded[id] {
            return (78, state.appearanceMode == .classicSemantic ? 64 : 0)
        }
        return (0, CarryStripView.closeZoneWidth)
    }

    /// 指针下是哪条卷帘条（收起的与带到每张桌面的都算）。
    private func stripUnder(_ point: NSPoint, preferring active: CGWindowID?) -> CGWindowID? {
        func contains(_ id: CGWindowID) -> Bool {
            stripFrame(id)?.insetBy(dx: -1, dy: -1).contains(point) == true
        }
        if let active, contains(active) { return active }
        for id in relays.keys where contains(id) {
            if let overlay = owner.shaded[id]?.overlay, !overlay.isVisible { continue }
            return id
        }
        return nil
    }

    private func sample(at point: NSPoint) -> GlancePointerSample {
        let active = intent.activeID
        let glanceFrame = active.flatMap { sessions[$0] }.flatMap { session in
            session.panel?.isVisible == true ? session.cardScreen : nil
        }
        if !hitTestsByGeometry {
            // 指针下最上层的窗口不是我们的：卷帘条或画面被别的窗口挡住了。
            let top = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
            if NSApp.window(withWindowNumber: top) == nil {
                return GlancePointerSample(strip: nil)
            }
        }
        let overGlance = glanceFrame?.contains(point) == true
        let strip = stripUnder(point, preferring: active)
        var overControls = false
        if let strip, let frame = stripFrame(strip) {
            let zone = controlsZone(strip)
            overControls = point.x - frame.minX < zone.left || frame.maxX - point.x < zone.right
        }
        return GlancePointerSample(strip: strip, overGlance: overGlance, overControls: overControls)
    }
}
