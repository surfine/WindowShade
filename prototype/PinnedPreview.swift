import AVFoundation
import Cocoa
import ApplicationServices
import ScreenCaptureKit

enum PinnedPreviewError: Error, LocalizedError {
    case noFocusedWindow
    case ownWindow
    case unsupportedWindow
    case noShareableContent
    case noSCWindow
    case noAXGeometry
    case screenRecordingDenied

    var errorDescription: String? {
        switch self {
        case .noFocusedWindow:
            return "没有可置顶预览的当前窗口"
        case .ownWindow:
            return "WindowShade 自己的窗口不能置顶预览"
        case .unsupportedWindow:
            return "此窗口不能置顶预览"
        case .noShareableContent:
            return "无法读取屏幕内容"
        case .noSCWindow:
            return "无法捕获这个窗口"
        case .noAXGeometry:
            return "无法读取窗口位置"
        case .screenRecordingDenied:
            return "需要屏幕录制权限"
        }
    }
}

private final class PinnedPreviewSession {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let title: String
    let axWindow: AXUIElement
    let panel: PinnedPreviewPanel
    let contentView: PinnedPreviewContentView
    let capture: WindowStreamCapture

    var scWindow: SCWindow
    var display: SCDisplay?
    var lastKnownFrame: NSRect
    var isInteracting = false
    var isDucked = false
    var watchdog: Timer?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var pendingExit: DispatchWorkItem?
    // 交互代数：每次进入交接自增；跨线程管线的每一跳都校验，过期即中止。
    var interactionEpoch: UInt64 = 0
    // watchdog 稳定门：上一拍读到的源窗口 frame，连续两拍一致才应用到面板。
    var pendingFrame: NSRect?
    // Mission Control/genie/全屏过渡期间 WindowServer 呈现坐标会"稳定但错误"
    // （比如 MC 缩略图排布），两拍稳定门本身挡不住。AX 确认后被判定为动画产物的
    // 候选帧记在这里，避免同一个错误候选帧每 0.2s 都重新发一次 AX 查询。
    var rejectedFrame: NSRect?
    var isConfirmingFrame = false
    // 交接管线完成前到达的点击：暂存，待面板真正透明+穿透后补发到真实窗口。
    var pendingClick: (point: CGPoint, count: Int)?
    // co-Space 不变量判定的短 TTL 缓存：watchdog 每 0.2s 触发，不必每拍都查 WindowServer。
    var spaceCheckAt: CFAbsoluteTime = 0
    // 面板当前应处的 Space（源窗口所在 Space）。nil 表示 SLS 符号不可用/尚未解析，
    // 此时面板留在创建时的 Space，不追随源窗口跨 Space 移动。
    var sourceSpaceID: UInt64?
    // 老板键（暂停全部置顶）挂起态：面板已 orderOut、capture 已停，watchdog 已停。
    // 恢复时按此位判断是否需要重启 capture/watchdog，而不是"取消置顶"（会话保留）。
    var isSuspended = false

    init(windowID: CGWindowID, pid: pid_t, bundleIdentifier: String, appName: String,
         title: String, axWindow: AXUIElement, scWindow: SCWindow, display: SCDisplay?,
         panel: PinnedPreviewPanel, contentView: PinnedPreviewContentView,
         capture: WindowStreamCapture, lastKnownFrame: NSRect) {
        self.windowID = windowID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.axWindow = axWindow
        self.scWindow = scWindow
        self.display = display
        self.panel = panel
        self.contentView = contentView
        self.capture = capture
        self.lastKnownFrame = lastKnownFrame
    }

    func invalidate() {
        watchdog?.invalidate()
        watchdog = nil
        pendingExit?.cancel()
        pendingExit = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

private struct PinnedPreviewTarget {
    let windowID: CGWindowID
    let axWindow: AXUIElement
}


struct PinnedPreviewMenuEntry {
    let id: CGWindowID
    let appName: String
    let title: String

    var displayTitle: String {
        let cleanAppName = cleanDisplayTitle(appName)
        let cleanTitle = cleanDisplayTitle(title)
        if cleanTitle.isEmpty { return cleanAppName.isEmpty ? "未命名窗口" : cleanAppName }
        if cleanAppName.isEmpty { return cleanTitle }
        return "\(cleanAppName) — \(cleanTitle)"
    }
}

final class PinnedPreviewController {
    typealias NoticeHandler = (_ message: String, _ log: String?) -> Void

    private let notice: NoticeHandler
    private let sessionsDidChange: () -> Void
    private var sessions: [CGWindowID: PinnedPreviewSession] = [:]
    private var currentTarget: PinnedPreviewTarget?
    // Space 切换动画窗口期：期间 CGWindow 坐标整屏滑动，watchdog 必须停止追踪，
    // 否则会把动画中间坐标当成"窗口移动"疯狂 setFrame + 重配 capture。
    private var spaceTransitionUntil: CFAbsoluteTime = 0
    // AX 同步调用可被忙 app 阻塞（超时 2s/次）；交接管线全部走这条串行队列，
    // 主线程只做面板状态切换。
    private let axWorkQueue = DispatchQueue(label: "WindowShade.pin-ax", qos: .userInteractive)
    private var pointerDuckingTimer: Timer?
    private var lastPointerDuckingID: CGWindowID?
    private var lockedDuckingID: CGWindowID?
    private var activePreviewID: CGWindowID?
    // 老板键：临时挂起全部置顶预览（隐藏面板 + 停止 capture），再按一次原样恢复。
    private var isSuspendedAll = false
    private let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager"
    ]

    init(notice: @escaping NoticeHandler, sessionsDidChange: @escaping () -> Void) {
        self.notice = notice
        self.sessionsDidChange = sessionsDidChange
    }

    var activePreviewCount: Int {
        sessions.count
    }

    func isPreviewing(id: CGWindowID) -> Bool {
        sessions[id] != nil
    }

    // 老板键掛起时 session 仍在（为了一键恢复），但 capture 已停——菜单缩略图这时
    // 不该去接一个收不到採样帧的 mirror layer，否则弹出一个永远空白的预览面板。
    func isSuspended(id: CGWindowID) -> Bool {
        sessions[id]?.isSuspended ?? false
    }

    func refreshCurrentTarget(reason: String) {
        guard let win = focusedWindow() else {
            wlog("pin-preview: target unchanged reason=\(reason) no-usable-focused-window")
            return
        }
        // 焦点窗口没变就不重新解析 windowID / 校验（CFEqual 只比较 AX token，
        // 不发 IPC）。真正置顶时 startPreview 还会完整校验一次，安全性不变。
        if let target = currentTarget, CFEqual(win, target.axWindow) { return }
        guard let id = windowID(of: win), isUsableTarget(win, id: id) else {
            wlog("pin-preview: target unchanged reason=\(reason) no-usable-focused-window")
            return
        }
        if currentTarget?.windowID != id {
            wlog("pin-preview: target changed reason=\(reason) id=\(id) title=\(cleanDisplayTitle(axTitle(win)))")
        }
        currentTarget = PinnedPreviewTarget(windowID: id, axWindow: win)
    }

    // 动态翻转：当前聚焦窗口已置顶时显示「取消置顶」，否则「置顶」。依赖 currentTarget
    // 已刷新——rebuildMenu / menuNeedsUpdate 在取标题前都会先 refreshCurrentTarget。
    func currentTargetMenuTitle() -> String {
        if let target = currentTarget, sessions[target.windowID] != nil {
            return "取消置顶当前窗口"
        }
        return "置顶当前窗口"
    }

    func pinCurrentTargetPreview() {
        guard hasAccessibilityPermission() else {
            notice("需要权限", "pin-preview: failed reason=accessibility")
            return
        }
        guard hasScreenRecordingPermission() else {
            notice("需要屏幕录制权限", "pin-preview: failed reason=screen-recording")
            return
        }
        refreshCurrentTarget(reason: "toggle")
        guard let target = currentTarget else {
            notice("没有可置顶预览窗口", "pin-preview: failed reason=no-focused-window")
            return
        }
        // 双向 toggle：已置顶则取消，未置顶则置顶。与 ⌃⌘C 折叠/展开对称。
        if sessions[target.windowID] != nil {
            stopPreview(id: target.windowID, reason: "toggle-unpin")
            return
        }
        startPreview(for: target.axWindow, id: target.windowID)
    }

    func stopAllPreviews(reason: String = "manual") {
        for id in Array(sessions.keys) {
            stopPreview(id: id, reason: reason)
        }
    }

    var isPinnedPreviewsSuspended: Bool { isSuspendedAll }

    // 菜单标题双态翻转，与折叠/置顶 toggle 同款用法。
    func suspendAllMenuTitle() -> String {
        isSuspendedAll ? "恢复置顶预览" : "暂时取消全部置顶"
    }

    // 老板键：暂停/恢复全部置顶预览。不是取消置顶——会话（真实窗口引用、frame
    // 记忆）保留，只是面板隐藏 + capture 停止（连带消除录屏指示器），再按一次
    // 原样恢复。与「全部取消置顶」是两个不同的操作，互不影响。
    func toggleSuspendAll() {
        if isSuspendedAll {
            resumeAllSuspended()
        } else {
            suspendAll()
        }
    }

    private func suspendAll() {
        guard !isSuspendedAll, !sessions.isEmpty else { return }
        isSuspendedAll = true
        for (id, session) in sessions {
            suspendSession(session, id: id)
        }
        pointerDuckingTimer?.invalidate()
        pointerDuckingTimer = nil
        wlog("pin-preview: suspend-all count=\(sessions.count)")
        sessionsDidChange()
    }

    private func suspendSession(_ session: PinnedPreviewSession, id: CGWindowID) {
        guard !session.isSuspended else { return }
        if session.isInteracting {
            endInteraction(id: id, sourceFrame: currentSourceFrame(id: id) ?? session.panel.frame)
        }
        session.isSuspended = true
        session.watchdog?.invalidate()
        session.watchdog = nil
        session.capture.stop()
        session.panel.ignoresMouseEvents = true
        session.panel.orderOut(nil)
        wlog("pin-preview: suspend id=\(id)")
    }

    private func resumeAllSuspended() {
        guard isSuspendedAll else { return }
        isSuspendedAll = false
        for (id, session) in Array(sessions) {
            resumeSession(session, id: id)
        }
        updatePointerDuckingTimer()
        wlog("pin-preview: resume-all count=\(sessions.count)")
        sessionsDidChange()
    }

    private func resumeSession(_ session: PinnedPreviewSession, id: CGWindowID) {
        guard session.isSuspended else { return }
        session.isSuspended = false
        // 挂起期间没有 watchdog 追踪源窗口；恢复前先确认它还在，关闭了就直接
        // 收掉这个会话而不是恢复一个指向已消失窗口的面板。
        guard let frame = currentSourceFrame(id: id) else {
            wlog("pin-preview: resume found closed source id=\(id)")
            stopPreview(id: id, reason: "resume-lost-source")
            return
        }
        session.lastKnownFrame = frame
        session.pendingFrame = nil
        session.rejectedFrame = nil
        session.panel.alphaValue = 1
        if !framesAlmostEqual(session.panel.frame, frame, tolerance: 1.0) {
            session.panel.setFrame(frame, display: true)
        }
        session.panel.ignoresMouseEvents = false
        session.panel.orderFrontRegardless()
        enforcePanelSpaceInvariant(session, reason: "resume")
        startWatchdog(for: session)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await session.capture.restart(window: session.scWindow, display: session.display,
                                                  width: frame.width, height: frame.height)
                wlog("pin-preview: resume id=\(id) frame=\(Self.format(frame))")
            } catch {
                self.notice("置顶预览恢复失败",
                            "pin-preview: resume capture failed id=\(id) \(error.localizedDescription)")
                self.stopPreview(id: id, reason: "resume-capture-failed")
            }
        }
    }

    func menuEntries() -> [PinnedPreviewMenuEntry] {
        sessions.values
            .sorted { lhs, rhs in
                let lhsApp = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
                if lhsApp == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsApp == .orderedAscending
            }
            .map { session in
                PinnedPreviewMenuEntry(id: session.windowID,
                                       appName: session.appName,
                                       title: session.title)
            }
    }

    func stopPreviewFromMenu(id: CGWindowID) {
        stopPreview(id: id, reason: "menu-item")
    }

    // 折叠截图前调用：该窗口若正被置顶实时捕获，先停止会话并返回 true。
    // 系统会在被捕获窗口的交通灯处叠加录屏标识；调用方应在停止后稍等标识
    // 消失再截图，避免把标识永久拍进卷帘条。未置顶时是无操作。
    func stopPreviewBeforeFoldCapture(id: CGWindowID) -> Bool {
        guard sessions[id] != nil else { return false }
        stopPreview(id: id, reason: "fold-capture")
        return true
    }

    // 菜单缩略图按窗口原始宽高比排版，返回当前已知的源窗口尺寸。
    func thumbnailSourceSize(id: CGWindowID) -> NSSize? {
        guard let session = sessions[id] else { return nil }
        let size = session.lastKnownFrame.size
        if size.width > 1, size.height > 1 { return size }
        let panelSize = session.panel.frame.size
        return panelSize.width > 1 && panelSize.height > 1 ? panelSize : nil
    }

    // 为菜单悬停缩略图构建实时预览视图：新建一个显示层挂到该会话正在运行的 capture 上做镜像，
    // 复用已有采样帧，不新建流。视图销毁或 detachThumbnail 时断开。
    func makeThumbnailPreviewView(frame: NSRect, id: CGWindowID) -> NSView? {
        guard let session = sessions[id] else { return nil }
        let layer = AVSampleBufferDisplayLayer()
        session.capture.mirrorLayer = layer
        return PinnedLivePreviewView(frame: frame, videoLayer: layer)
    }

    func detachThumbnail(id: CGWindowID) {
        sessions[id]?.capture.mirrorLayer = nil
    }

    func stopPreviews(forPID pid: pid_t, reason: String) {
        for id in sessions.filter({ $0.value.pid == pid }).map(\.key) {
            stopPreview(id: id, reason: reason)
        }
    }

    func refreshAll(reason: String) {
        for id in Array(sessions.keys) {
            watchdogTick(id: id, reason: reason)
        }
    }

    // AppDelegate 在 activeSpaceChanged 时调用，开启动画抑制窗口期。
    func noteSpaceTransition() {
        spaceTransitionUntil = CFAbsoluteTimeGetCurrent() + 0.6
        // Space 已经变了，之前锁定的 ducking 目标可能是刚离开的 Space 上的面板；
        // 清掉缓存，下一拍 pointerDuckingTick 用 Space 过滤后的结果重新判定。
        lockedDuckingID = nil
        lastPointerDuckingID = nil
    }

    private var isInSpaceTransition: Bool {
        CFAbsoluteTimeGetCurrent() < spaceTransitionUntil
    }

    // 面板与源窗口同 Space 的不变量（与折叠条 overlay 的 enforceOverlaySpaceInvariant
    // 同构）：源窗口被拖到别的 Space（比如在 Mission Control 里）就让面板跟过去；
    // 面板自己漂移了（防御性，正常不会发生）就搬回源 Space。SLS 符号不可用时
    // 整个不变量不生效，面板留在创建时的 Space。0.5s TTL：watchdog 每 0.2s 触发，
    // 不必每拍都查 WindowServer。
    private func enforcePanelSpaceInvariant(_ session: PinnedPreviewSession, reason: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - session.spaceCheckAt >= 0.5 else { return }
        session.spaceCheckAt = now
        let mover = PrivateSLSWindowMover.shared
        guard let sourceSpaceID = mover.windowSpace(id: session.windowID),
              let panelID = cgWindowID(for: session.panel) else { return }
        if session.sourceSpaceID != sourceSpaceID {
            if mover.moveWindow(id: panelID, toSpace: sourceSpaceID) {
                wlog("pin-preview: space follow id=\(session.windowID) from=\(session.sourceSpaceID.map(String.init) ?? "-") to=\(sourceSpaceID) reason=\(reason)")
                session.sourceSpaceID = sourceSpaceID
            }
            return
        }
        if let panelSpace = mover.windowSpace(id: panelID), panelSpace != sourceSpaceID,
           mover.moveWindow(id: panelID, toSpace: sourceSpaceID) {
            wlog("pin-preview: space corrected id=\(session.windowID) panel=\(panelSpace) expected=\(sourceSpaceID) reason=\(reason)")
        }
    }

    private func startPreview(for axWindow: AXUIElement, id: CGWindowID) {
        do {
            try validateAXWindow(axWindow, id: id)
        } catch {
            notice(error.localizedDescription, "pin-preview: failed reason=\(error.localizedDescription)")
            return
        }

        var pid: pid_t = 0
        AXUIElementGetPid(axWindow, &pid)
        let appName = appDisplayName(pid: pid)
        let bundleID = appBundleID(pid: pid)
        let title = cleanDisplayTitle(axTitle(axWindow))

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // 折叠/预热之后紧接着置顶，多数情况下 ShareableContentCache 已经是热的，
                // 走它省掉一次全系统枚举；缓存未命中或系统低于 14 时退回原始直接调用。
                let content: SCShareableContent
                if #available(macOS 14.0, *), let cached = await ShareableContentCache.shared.content(requiring: id) {
                    content = cached
                } else {
                    content = try await ShareableContentLoader.current()
                }
                guard let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                    throw PinnedPreviewError.noSCWindow
                }
                let display = Self.bestDisplay(for: scWindow, displays: content.displays)
                self.installPreview(id: id, pid: pid, bundleID: bundleID, appName: appName,
                                    title: title, axWindow: axWindow, scWindow: scWindow,
                                    display: display)
            } catch {
                self.notice(error.localizedDescription,
                            "pin-preview: failed reason=\(error.localizedDescription)")
            }
        }
    }

    private func validateAXWindow(_ axWindow: AXUIElement, id: CGWindowID) throws {
        var pid: pid_t = 0
        guard AXUIElementGetPid(axWindow, &pid) == .success, pid > 0 else {
            throw PinnedPreviewError.unsupportedWindow
        }
        guard pid != getpid() else { throw PinnedPreviewError.ownWindow }
        let bundleID = appBundleID(pid: pid)
        guard !excludedBundleIDs.contains(bundleID) else { throw PinnedPreviewError.unsupportedWindow }
        guard axRole(axWindow) == kAXWindowRole as String else { throw PinnedPreviewError.unsupportedWindow }
        guard let size = axSize(axWindow), size.width >= 80, size.height >= 80 else {
            throw PinnedPreviewError.unsupportedWindow
        }
        guard let info = cgWindowInfo(id), sourceInfoIsUsable(info) else {
            throw PinnedPreviewError.unsupportedWindow
        }
    }

    private func isUsableTarget(_ axWindow: AXUIElement, id: CGWindowID) -> Bool {
        do {
            try validateAXWindow(axWindow, id: id)
            return true
        } catch {
            return false
        }
    }

    private func installPreview(id: CGWindowID, pid: pid_t, bundleID: String,
                                appName: String, title: String, axWindow: AXUIElement,
                                scWindow: SCWindow, display: SCDisplay?) {
        guard sessions[id] == nil else { return }
        guard let frame = currentSourceFrame(id: id) ?? Optional(cocoaFrame(fromWindowServerBounds: scWindow.frame)) else {
            notice("无法读取窗口位置", "pin-preview: failed reason=no-frame id=\(id)")
            return
        }

        let capture = WindowStreamCapture()
        let panel = PinnedPreviewPanel(frame: frame)
        let contentView = PinnedPreviewContentView(videoLayer: capture.videoLayer)
        panel.contentView = contentView

        let session = PinnedPreviewSession(windowID: id, pid: pid, bundleIdentifier: bundleID,
                                           appName: appName, title: title, axWindow: axWindow,
                                           scWindow: scWindow, display: display, panel: panel,
                                           contentView: contentView, capture: capture,
                                           lastKnownFrame: frame)
        contentView.onMouseEntered = { [weak self] in
            self?.beginInteraction(id: id)
        }
        contentView.onMouseMoved = { [weak self] in
            self?.beginInteraction(id: id)
        }
        contentView.onMouseExited = { [weak self] in
            self?.scheduleInteractionExitCheck(id: id)
        }
        contentView.onMouseDown = { [weak self] event in
            self?.passThroughInitialClick(id: id, event: event)
        }
        sessions[id] = session
        panel.orderFrontRegardless()
        enforcePanelSpaceInvariant(session, reason: "install")
        startWatchdog(for: session)
        updatePointerDuckingTimer()
        sessionsDidChange()
        wlog("pin-preview: start id=\(id) app=\(appName) title=\(title) frame=\(format(frame))")

        Task { @MainActor [weak self] in
            do {
                try await capture.start(window: scWindow, display: display)
                wlog("pin-preview: capture started id=\(id) size=\(Int(frame.width))x\(Int(frame.height))")
            } catch {
                self?.notice("置顶预览失败", "pin-preview: capture failed id=\(id) \(error.localizedDescription)")
                self?.stopPreview(id: id, reason: "capture-failed")
            }
        }
    }

    private func startWatchdog(for session: PinnedPreviewSession) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak session] _ in
            guard let session else { return }
            self?.watchdogTick(id: session.windowID, reason: "watchdog")
        }
        timer.tolerance = 0.05
        session.watchdog = timer
    }

    private func watchdogTick(id: CGWindowID, reason: String) {
        guard let session = sessions[id], !session.isSuspended else { return }
        // Space 切换动画期间 CGWindow 坐标整屏滑动，全部跳过（也不更新 lastKnownFrame，
        // 避免把动画中间坐标记成稳定值）；窗口期结束后下一次 tick 一次性校正。
        if isInSpaceTransition { return }
        enforcePanelSpaceInvariant(session, reason: reason)
        guard let frame = currentSourceFrame(id: id) else {
            wlog("pin-preview: closed lost source id=\(id)")
            stopPreview(id: id, reason: "lost-source")
            return
        }
        if session.isInteracting {
            // 交互中窗口由用户直接操作，持续跟随（exit 时要用）；稳定门/AX 确认不适用。
            session.lastKnownFrame = frame
            session.pendingFrame = nil
            session.rejectedFrame = nil
            return
        }
        // 稳定门：frame 需与上一拍一致（连续两拍相同）才应用。最小化/恢复 genie、
        // 全屏过渡等动画期间坐标每拍都在变，绝不能把面板 setFrame 成动画中间态
        // （曾把 855x502 的面板追成 Dock 缩略图大小的 109x97）。
        let isStable = framesAlmostEqual(frame, session.lastKnownFrame, tolerance: 1.0)
            || (session.pendingFrame.map { framesAlmostEqual($0, frame, tolerance: 1.0) } ?? false)
        session.pendingFrame = frame
        guard isStable else { return }
        session.pendingFrame = nil
        guard !framesAlmostEqual(session.lastKnownFrame, frame, tolerance: 1.0) else { return }
        confirmAndApplyFrame(session: session, id: id, frame: frame, reason: reason)
    }

    // Mission Control 缩略排布、genie、全屏过渡期间 WindowServer 呈现坐标会"稳定但
    // 错误"（MC 把窗口缩放后静止摆放，两拍稳定门本身挡不住），但窗口在 app 语境里
    // 的逻辑几何（AX position/size）不受这类纯合成层变换影响。套用一个与
    // lastKnownFrame 不同的候选帧前，先用 AX 读数确认二者一致，不一致就判定为动画
    // 产物、丢弃候选帧。AX 调用可能阻塞（忙 app），必须在 axWorkQueue 上做。
    private func confirmAndApplyFrame(session: PinnedPreviewSession, id: CGWindowID,
                                      frame: NSRect, reason: String) {
        guard !session.isConfirmingFrame else { return }
        if let rejected = session.rejectedFrame, framesAlmostEqual(rejected, frame, tolerance: 1.0) {
            return
        }
        session.isConfirmingFrame = true
        let axWindow = session.axWindow
        axWorkQueue.async { [weak self] in
            let axFrame: NSRect? = axPosition(axWindow).flatMap { pos in
                axSize(axWindow).map { size in cocoaFrame(fromAXPosition: pos, size: size) }
            }
            DispatchQueue.main.async {
                guard let self, let session = self.sessions[id] else { return }
                session.isConfirmingFrame = false
                // AX 读取失败（忙 app 超时等）时不因此卡死，退回信任 WindowServer 坐标，
                // 与改动前行为一致。
                guard let axFrame, !framesAlmostEqual(axFrame, frame, tolerance: 2.0) else {
                    session.rejectedFrame = nil
                    self.applyConfirmedFrame(session: session, id: id, frame: frame, reason: reason)
                    return
                }
                session.rejectedFrame = frame
                wlog("pin-preview: watchdog rejected animated frame id=\(id) cg=\(Self.format(frame)) ax=\(Self.format(axFrame)) reason=\(reason)")
            }
        }
    }

    private func applyConfirmedFrame(session: PinnedPreviewSession, id: CGWindowID,
                                     frame: NSRect, reason: String) {
        session.lastKnownFrame = frame
        guard !framesAlmostEqual(session.panel.frame, frame, tolerance: 1.0) else { return }
        let old = session.panel.frame
        logIfSlow("pin-watchdog frame-sync id=\(id)") {
            session.panel.setFrame(frame, display: true)
            session.capture.updateSize(width: frame.width, height: frame.height, display: session.display)
        }
        updateDucking(activeID: activeInteractionID())
        wlog("pin-preview: frame changed id=\(id) old=\(format(old)) new=\(format(frame)) reason=\(reason)")
    }

    private func beginInteraction(id: CGWindowID) {
        guard let session = sessions[id], !session.isInteracting, !session.isDucked else { return }
        if let activePreviewID, activePreviewID != id {
            guard let active = sessions[activePreviewID],
                  !active.panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else {
                return
            }
            endInteraction(id: activePreviewID,
                           sourceFrame: currentSourceFrame(id: activePreviewID) ?? active.panel.frame)
            return
        }
        session.pendingExit?.cancel()
        session.pendingExit = nil
        session.isInteracting = true
        session.interactionEpoch &+= 1
        let epoch = session.interactionEpoch
        activePreviewID = id
        lockedDuckingID = id
        updateDucking(activeID: id)
        wlog("pin-preview: enter interact id=\(id) frame=\(format(session.panel.frame))")

        // 先把真实窗口定位到面板处、聚焦、并抬到全局最前，此时面板仍不透明地盖着它，
        // 保证透明穿透露出的一定是这个置顶窗口。顺序不变，但同步 AX 调用（忙 app 可各阻塞
        // 至 2s）全部放到 axWorkQueue；主线程只做 AppKit 状态切换，期间实时画面继续显示。
        //
        // kAXRaiseAction 只在所属 app 内部重排 z 序，所以中间必须 activate 所属 app；
        // 且先把置顶窗口设为 focused/main，多窗口 app 激活时上浮的才是它而非兄弟窗口。
        let frame = session.panel.frame
        let targetPosition = axPosition(fromCocoaFrame: frame)
        let axWindow = session.axWindow
        let pid = session.pid

        // 管线每一跳都校验 epoch/isInteracting；交互被取消（鼠标已离开、会话被停止）
        // 时中止，面板保持不透明的安全侧。只能在主线程调用。
        let stillValid: () -> Bool = { [weak self] in
            guard let live = self?.sessions[id] else { return false }
            return live.isInteracting && live.interactionEpoch == epoch
        }

        axWorkQueue.async { [weak self] in
            guard let self else { return }
            let proceed = DispatchQueue.main.sync { stillValid() }
            guard proceed else { return }
            logIfSlow("pin-interact ax-geometry id=\(id)") {
                _ = setAXSize(axWindow, frame.size)
                setAXPosition(axWindow, targetPosition)
                focusAXWindow(axWindow, pid: pid)
            }
            DispatchQueue.main.async {
                guard stillValid() else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }
                self.axWorkQueue.async {
                    logIfSlow("pin-interact ax-raise id=\(id)") {
                        raiseAXWindow(axWindow)
                    }
                    DispatchQueue.main.async {
                        guard stillValid(), let session = self.sessions[id] else { return }
                        // 真实窗口就位后再让面板淡出并放行鼠标，把交互交给它。
                        session.capture.stop()
                        session.panel.alphaValue = 0.02
                        session.panel.hasShadow = false
                        session.panel.ignoresMouseEvents = true
                        self.installMouseMonitorsIfNeeded(for: session)
                        // 面板已穿透，补发交接期间暂存的点击。
                        if let pending = session.pendingClick {
                            session.pendingClick = nil
                            Self.postSyntheticClick(at: pending.point, clickCount: pending.count)
                        }
                    }
                }
            }
        }
    }

    private func passThroughInitialClick(id: CGWindowID, event: NSEvent) {
        guard let session = sessions[id] else { return }
        // 面板与源窗口现在总是同 Space（enforcePanelSpaceInvariant），点击面板
        // 就是点在源窗口所在的当前 Space 上，不再需要跨 Space 召唤/跳转分支。
        let windowPoint = event.locationInWindow
        let screenRect = session.panel.convertToScreen(NSRect(origin: windowPoint, size: .zero))
        let axPoint = CGPoint(x: screenRect.origin.x,
                              y: coordinateBaselineY() - screenRect.origin.y)

        // 交接管线是异步的：点击先暂存，待面板真正透明+穿透后（管线末端）再补发。
        // 立刻补发会再次打在尚未穿透的面板上，触发 mouseDown 自循环。
        session.pendingClick = (axPoint, max(event.clickCount, 1))
        beginInteraction(id: id)
        wlog("pin-preview: pass-through click queued id=\(id) ax=(\(Int(axPoint.x)),\(Int(axPoint.y)))")
    }

    private static func postSyntheticClick(at axPoint: CGPoint, clickCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseDown,
                               mouseCursorPosition: axPoint,
                               mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            down?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                let up = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseUp,
                                 mouseCursorPosition: axPoint,
                                 mouseButton: .left)
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                up?.post(tap: .cghidEventTap)
            }
        }
    }

    private func scheduleInteractionExitCheck(id: CGWindowID) {
        guard let session = sessions[id], session.isInteracting else { return }
        session.pendingExit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishInteractionIfMouseOutside(id: id)
        }
        session.pendingExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func finishInteractionIfMouseOutside(id: CGWindowID) {
        guard activePreviewID == id else { return }
        guard let session = sessions[id], session.isInteracting else { return }
        let frame = currentSourceFrame(id: id) ?? session.panel.frame
        if frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            return
        }
        endInteraction(id: id, sourceFrame: frame)
    }

    private func endInteraction(id: CGWindowID, sourceFrame: NSRect) {
        guard let session = sessions[id], session.isInteracting else { return }
        let wasActive = activePreviewID == id
        session.isInteracting = false
        // 令在途的交接管线（axWorkQueue 上的跳板）过期中止，丢弃未补发的点击。
        session.interactionEpoch &+= 1
        session.pendingClick = nil
        if wasActive {
            activePreviewID = nil
            lockedDuckingID = nil
        }
        session.pendingExit?.cancel()
        session.pendingExit = nil
        removeMouseMonitors(for: session)
        // Space 过渡期间 currentSourceFrame 读到的是滑动动画中间值；用交接前的稳定坐标。
        let stableFrame = isInSpaceTransition ? session.lastKnownFrame : sourceFrame
        session.lastKnownFrame = stableFrame
        logIfSlow("pin-interact exit-restore id=\(id)") {
            session.panel.setFrame(stableFrame, display: true)
            session.panel.ignoresMouseEvents = false
            session.panel.hasShadow = true
            session.panel.level = .floating
            session.panel.orderFrontRegardless()
        }
        if wasActive {
            updateDucking(activeID: nil)
        }
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            // 老板键可能在这次退出交互的同一拍里把会话挂起（suspendSession 先调用
            // endInteraction 收尾再停 capture）：挂起态不重启 capture，否则刚被
            // 老板键停掉的流又被这里重新拉起来。
            guard !session.isSuspended else { return }
            do {
                try await session.capture.restart(window: session.scWindow, display: session.display,
                                                  width: stableFrame.width, height: stableFrame.height)
                session.panel.alphaValue = 1
                wlog("pin-preview: exit interact id=\(id) frame=\(Self.format(stableFrame))")
                self.sessionsDidChange()
            } catch {
                self.notice("置顶预览恢复失败",
                            "pin-preview: restart failed id=\(id) \(error.localizedDescription)")
                self.stopPreview(id: id, reason: "restart-failed")
            }
        }
    }

    private func installMouseMonitorsIfNeeded(for session: PinnedPreviewSession) {
        guard session.globalMouseMonitor == nil, session.localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        session.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleInteractionExitCheck(id: session.windowID)
            }
        }
        session.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.scheduleInteractionExitCheck(id: session.windowID)
            return event
        }
    }

    private func removeMouseMonitors(for session: PinnedPreviewSession) {
        if let monitor = session.globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            session.globalMouseMonitor = nil
        }
        if let monitor = session.localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            session.localMouseMonitor = nil
        }
    }

    private func activeInteractionID() -> CGWindowID? {
        if let activePreviewID, sessions[activePreviewID]?.isInteracting == true {
            return activePreviewID
        }
        return nil
    }

    private func updatePointerDuckingTimer() {
        if sessions.count > 1 {
            guard pointerDuckingTimer == nil else { return }
            // 30Hz 足够跟手（悬停 ducking 延迟 ~33ms 无感）；120Hz + 零容差会让
            // 多预览场景下主线程持续满频醒来。
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.pointerDuckingTick()
            }
            timer.tolerance = 1.0 / 120.0
            pointerDuckingTimer = timer
        } else {
            pointerDuckingTimer?.invalidate()
            pointerDuckingTimer = nil
            lastPointerDuckingID = nil
            lockedDuckingID = nil
            if activeInteractionID() == nil {
                restoreDuckedPreviews(reason: "single-preview")
            }
        }
    }

    private func pointerDuckingTick() {
        if let activeID = activeInteractionID() {
            lockedDuckingID = activeID
            lastPointerDuckingID = activeID
            updateDucking(activeID: activeID)
            return
        }

        let mouse = NSEvent.mouseLocation
        if let lockedID = lockedDuckingID, let locked = sessions[lockedID] {
            if locked.panel.frame.insetBy(dx: -2, dy: -2).contains(mouse) {
                lastPointerDuckingID = lockedID
                updateDucking(activeID: lockedID)
                return
            }
            lockedDuckingID = nil
        }

        guard let hoverID = pointerHoveredPreviewID() else {
            if lastPointerDuckingID != nil {
                lastPointerDuckingID = nil
                lockedDuckingID = nil
                restoreDuckedPreviews(reason: "pointer-outside")
            }
            return
        }

        lockedDuckingID = hoverID
        lastPointerDuckingID = hoverID
        updateDucking(activeID: hoverID)
    }

    // 面板现在按 Space 分布（不再全局跟随），绝对屏幕坐标在不同 Space 间可以重叠：
    // 命中测试和 duck 重叠判定都必须先过滤到「当前 Space」的会话，否则会误判/误
    // duck 一个根本不在眼前的 Space 上的面板。
    private func sessionIsOnCurrentSpace(_ session: PinnedPreviewSession,
                                         mover: PrivateSLSWindowMover,
                                         cache: inout [CGDirectDisplayID: UInt64?]) -> Bool {
        guard let sourceSpaceID = session.sourceSpaceID else { return true }  // SLS 不可用：回退现状
        guard let screen = session.panel.screen ?? NSScreen.main,
              let display = displayID(for: screen) else { return true }
        if cache[display] == nil {
            cache[display] = mover.currentSpace(displayID: display)
        }
        guard let activeSpaceID = cache[display] ?? nil else { return true }
        return activeSpaceID == sourceSpaceID
    }

    private func pointerHoveredPreviewID() -> CGWindowID? {
        let mouse = NSEvent.mouseLocation
        let mover = PrivateSLSWindowMover.shared
        var spaceCache: [CGDirectDisplayID: UInt64?] = [:]
        let hits = sessions.filter { _, session in
            !session.isDucked && session.panel.isVisible && session.panel.frame.contains(mouse)
                && sessionIsOnCurrentSpace(session, mover: mover, cache: &spaceCache)
        }
        return hits.min { lhs, rhs in
            lhs.value.panel.orderedIndex < rhs.value.panel.orderedIndex
        }?.key
    }

    private func updateDucking(activeID: CGWindowID?) {
        guard let activeID, let active = sessions[activeID] else {
            restoreDuckedPreviews(reason: "no-active")
            return
        }

        let activeFrame = active.panel.frame
        if active.isDucked {
            restoreDuckedPreview(active, id: activeID, reason: "active")
        }
        active.panel.level = .floating
        active.panel.orderFrontRegardless()
        let mover = PrivateSLSWindowMover.shared
        var spaceCache: [CGDirectDisplayID: UInt64?] = [:]
        for (id, session) in sessions where id != activeID {
            guard sessionIsOnCurrentSpace(session, mover: mover, cache: &spaceCache) else { continue }
            let shouldDuck = activeFrame.intersects(session.panel.frame)
            if shouldDuck, !session.isDucked {
                session.isDucked = true
                session.panel.ignoresMouseEvents = true
                session.panel.orderOut(nil)
                wlog("pin-preview: duck id=\(id) active=\(activeID)")
            } else if !shouldDuck, session.isDucked {
                restoreDuckedPreview(session, id: id, reason: "no-overlap")
            }
        }
    }

    private func restoreDuckedPreviews(reason: String) {
        for (id, session) in sessions where session.isDucked {
            restoreDuckedPreview(session, id: id, reason: reason)
        }
    }

    private func restoreDuckedPreview(_ session: PinnedPreviewSession, id: CGWindowID, reason: String) {
        session.isDucked = false
        guard !session.isInteracting else {
            session.panel.ignoresMouseEvents = true
            return
        }
        session.panel.ignoresMouseEvents = false
        session.panel.level = .floating
        session.panel.orderFrontRegardless()
        wlog("pin-preview: unduck id=\(id) reason=\(reason)")
    }

    private func stopPreview(id: CGWindowID, reason: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.invalidate()
        session.capture.stop()
        session.panel.close()
        if activePreviewID == id { activePreviewID = nil }
        if lockedDuckingID == id { lockedDuckingID = nil }
        if lastPointerDuckingID == id { lastPointerDuckingID = nil }
        restoreDuckedPreviews(reason: "stop-\(id)")
        updatePointerDuckingTimer()
        sessionsDidChange()
        wlog("pin-preview: stop id=\(id) reason=\(reason)")
    }

    private func currentSourceFrame(id: CGWindowID) -> NSRect? {
        guard let info = cgWindowInfo(id), sourceInfoIsUsable(info), let bounds = cgWindowBounds(info) else {
            return nil
        }
        return cocoaFrame(fromWindowServerBounds: bounds)
    }

    private func sourceInfoIsUsable(_ info: [String: Any]) -> Bool {
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer == 0 else { return false }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.05 else { return false }
        guard let bounds = cgWindowBounds(info), bounds.width >= 80, bounds.height >= 80 else { return false }
        return true
    }

    private static func bestDisplay(for window: SCWindow, displays: [SCDisplay]) -> SCDisplay? {
        func area(_ display: SCDisplay) -> CGFloat {
            let hit = display.frame.intersection(window.frame)
            return hit.isNull ? 0 : hit.width * hit.height
        }
        return displays.max { area($0) < area($1) }
    }

    private static func format(_ frame: NSRect) -> String {
        "(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
    }

    private func format(_ frame: NSRect) -> String {
        Self.format(frame)
    }
}
