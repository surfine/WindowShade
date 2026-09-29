// 侧拉（iPadOS 的 Slide Over）：一扇窗口靠在屏幕左边或右边，浮在所有 App 前面；
// 甩出屏幕边就收起来，边上留一个小把手；点一下把手、在把手上往里划，或按快捷键，它就滑回来。
//
// 做法（2026-09-26 实测后定的）：
// - 真窗口本身挪：辅助功能能把窗口推到屏幕左右边外，只留几点在屏幕里（两块屏上都实测不回弹），
//   所以收起、拉出都是真窗口带着速度滑（WindowGlide），不用截图替身，也不用最小化或隐藏整个 App。
// - 浮在前面借用置顶：真窗口的层级改不了（跨进程的改动在 SIP 下无效），置顶是我们自己的实时画面面板，
//   指针一进去就把真窗口交到前面。拉出来时置顶，收起时停掉置顶。
// - 只有一扇（按单扇浮窗的方式）；再侧拉另一扇，前一扇退出侧拉，留在原处。
// - 往哪边靠：离窗口近的那一边；那一边挨着别的屏幕时换另一边（推出边外会跑到那块屏上）。
// - 带到每张桌面：别的 App 的窗口挪不到另一张桌面（2026-09-26 实测：最小化再还原仍回原桌面，
//   我们的连接去挪系统直接拒绝）。所以把手出现在每张桌面；在窗口所在的桌面拉出来的是真窗口，
//   在别的桌面拉出来的是它的实时画面（SlideOverMirror），点一下回到它所在的桌面接着用。
//   App 在 Dock 里设成“所有桌面”时，窗口本来就在每张桌面上，处处都是真窗口。

import Cocoa
import ApplicationServices
import AVFoundation
import ScreenCaptureKit

@MainActor
final class SlideOverController {
    enum Side: String { case left, right }

    private struct Docked {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        var side: Side
        /// 靠边时的外框（AX 坐标）。
        var frame: CGRect
        var hidden: Bool
        let display: CGDirectDisplayID?
        let restorePin: Bool
    }

    unowned let owner: AppDelegate
    private var docked: Docked?
    private var glide: WindowGlide?
    private let tab = SlideOverTab()
    /// 拉出来时窗口外面那一圈玻璃边框和角上的把手（iPadOS 的样子，见 SlideOverChrome）。
    private let chrome = SlideOverChrome()
    /// 拖着边框挪窗口：起点和写位置的那条链。
    private var chromeDrag: (start: CGRect, writer: LatestValueWriter<CGPoint>)?
    /// 拖着把手改大小：起点、这块屏的可用区域、写入那条队列记下的实际外框、写外框的那条链、
    /// App 是否没按要的尺寸来（这时边框按窗口实际的样子摆，不跟着手）。
    private var resizing: (start: CGRect, area: CGRect, memory: ResizeMemory, writer: LatestValueWriter<CGRect>, clamped: Bool)?
    let dropHint = SlideOverDropHint()
    private var mirror: SlideOverMirror?
    /// 点了实时画面、正在切去窗口所在的桌面：到了就把真窗口拉出来。
    private var openingAtHome = false
    private var generation: UInt64 = 0
    private var maintenance: Timer?
    private var dragWriter: SlideOverDragWriter?
    private var draggingMirror = false
    /// 正按着标题栏拖着的那扇（dragMoved 起，到松手）：这期间边框收着，定时检查不把它挂回来。
    private var titleDragging: CGWindowID?
    private var edgeDrag: (start: CGRect, latest: CGRect, wasHidden: Bool)?
    private var spaceObserver: NSObjectProtocol?
    /// 收起后留在屏幕里的宽度：几乎看不见，但窗口还算在这块屏上。
    static let peek: CGFloat = 4
    /// 窗口离屏幕边：10 点玻璃边框 + 8 点缝（iPad 上边框外沿离屏幕边 8 点）。
    static let inset: CGFloat = SlideOverChrome.thickness + 8
    static let minimumWidth: CGFloat = 320

    init(owner: AppDelegate) {
        self.owner = owner
        tab.onReveal = { [weak self] in self?.reveal(reason: "tab") }
        tab.onBegin = { [weak self] in self?.beginEdgeDrag() }
        tab.onDrag = { [weak self] delta in self?.updateEdgeDrag(inward: delta) }
        tab.onEnd = { [weak self] speed, cancel in self?.endEdgeDrag(inwardVelocity: speed, cancelled: cancel) }
        chrome.onMoveBegin = { [weak self] in self?.beginChromeDrag() }
        chrome.onMove = { [weak self] delta in self?.updateChromeDrag(delta) }
        chrome.onMoveEnd = { [weak self] velocity in self?.endChromeDrag(velocity: velocity) }
        chrome.onResizeBegin = { [weak self] in self?.beginResize() }
        chrome.onResize = { [weak self] delta in self?.updateResize(delta) }
        chrome.onResizeEnd = { [weak self] in self?.endResize() }
        maintenance = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.validateWindow() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
    }

    var dockedWindowID: CGWindowID? { docked?.id }
    /// 刘海的一排里要显示的：哪扇窗、哪个 App。
    var notchInfo: (id: CGWindowID, pid: pid_t)? { docked.map { ($0.id, $0.pid) } }
    var isHidden: Bool { docked?.hidden ?? false }
    func isSlideOver(_ id: CGWindowID) -> Bool { docked?.id == id }
    /// 探针用：把手是否挂着、靠边时的外框。
    var tabVisible: Bool { tab.isVisible }
    var mirrorVisible: Bool { mirror?.isVisible ?? false }
    var mirrorFrames: UInt64 { mirror?.deliveredFrames ?? 0 }
    var mirrorFrame: NSRect? { mirror?.frame }
    var dockedFrame: CGRect? { docked?.frame }
    var chromeVisible: Bool { chrome.isVisible }
    var chromeFrameAX: CGRect? { chrome.frameAX }
    var chromeHandleFrame: NSRect? { chrome.handleFrame }
    var chromeCornerRadius: CGFloat { chrome.cornerRadius }
    var menuTitle: String { docked == nil ? "侧拉当前窗口" : (docked!.hidden ? "拉出侧拉的窗口" : "收起侧拉的窗口") }

    // MARK: - 入口

    /// 快捷键：没有侧拉的窗口时，把当前窗口侧拉；有就在收起和拉出之间切换。
    func toggleCurrentWindow() {
        if let current = docked {
            if !windowHere(current) {
                if mirrorVisible { dismissMirror(velocity: .zero) } else { reveal(reason: "shortcut") }
            } else if current.hidden {
                show(reason: "shortcut")
            } else {
                hide(velocity: .zero, reason: "shortcut")
            }
            return
        }
        generation &+= 1
        let request = generation
        // 找前台窗口要问那个 App，放到后台去问，主线程不等。
        DispatchQueue.global(qos: .userInitiated).async {
            let win = focusedWindow()
            let id = win.flatMap { windowID(of: $0) }
            var pid: pid_t = 0
            if let win { AXUIElementGetPid(win, &pid) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.generation == request, self.docked == nil else { return }
                    guard let win, let id else {
                        self.owner.quietNotice("没有可以侧拉的窗口", log: "slide-over: no focused window")
                        return
                    }
                    self.enter(win, id: id, pid: pid)
                }
            }
        }
    }

    /// 把这扇窗口侧拉：滑到靠边的位置，置顶。
    /// side：想靠哪边（从启动台拖到哪一边）；那边挨着别的屏幕时照常自己挑。
    func enter(_ win: AXUIElement, id: CGWindowID, pid: pid_t, side preferred: Side? = nil, on targetScreen: NSScreen? = nil) {
        dropHint.cancel()
        guard let info = cgWindowInfo(id), let current = cgWindowBounds(info),
              let screen = targetScreen ?? screenForAXWindow(pos: current.origin, size: current.size) else { return }
        guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid else { return }
        let size = current.size
        let chosen = preferred.flatMap { Self.neighborFree($0, screen) ? $0 : nil } ?? Self.side(for: current, on: screen)
        guard let side = chosen else {
            owner.quietNotice("两边都挨着别的屏幕，侧拉没有地方收", log: "slide-over: both sides have displays")
            return
        }
        if var existing = docked, existing.id == id {
            existing.side = side
            existing.frame = Self.dockedFrame(width: existing.frame.width, height: existing.frame.height, side: side, on: screen)
            existing.hidden = false
            docked = existing
            tab.hide(); unpin()
            move(to: existing.frame, from: current, velocity: .zero) { [weak self] in self?.pin() }
            return
        }
        if docked != nil { exit(reason: "replaced") }
        generation &+= 1
        let frame = Self.dockedFrame(width: min(size.width, screen.visibleFrame.width * 0.4), height: size.height, side: side, on: screen)
        guard SlideOverRecovery.record(id: id, pid: pid, frame: frame) else {
            owner.quietNotice("暂时不能侧拉这个窗口，请再试一次", log: "slide-over: no durable recovery record")
            return
        }
        docked = Docked(id: id, pid: pid, element: win, side: side, frame: frame, hidden: false, display: displayID(for: screen), restorePin: owner.pinnedPreviewController.isPreviewing(id: id))
        chrome.cornerRadius = SlideOverChrome.defaultCornerRadius
        Task { @MainActor [weak self] in
            guard let radius = await SlideOverChrome.measureCornerRadius(id: id), let self, self.docked?.id == id else { return }
            self.chrome.cornerRadius = radius
            wlog(String(format: "slide-over: window corner radius %.1f", radius))
        }
        owner.cancelRestorePin(for: id)
        owner.gestures.forgetPlacement(for: id)
        wlog("slide-over: enter id=\(id) side=\(side.rawValue) frame=\(frame)")
        move(to: frame, from: current, velocity: .zero) { [weak self] in
            self?.pin()
            self?.refreshTab()
            // 第一次侧拉：教一下角上的把手和边框。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    guard let self, self.docked?.id == id, self.docked?.hidden == false else { return }
                    _ = self.owner.notch.teach(.slideOverHandle)
                }
            }
        }
    }

    /// 收到屏幕边外，边上留一个把手。velocity：甩出去的速度（AX 坐标，点/秒）。
    func hide(velocity: CGVector, reason: String) {
        guard var current = docked, !current.hidden else { return }
        guard let now = frameNow(current), let screen = screenForDisplayID(current.display) else { return }
        // 被人挪过、改过大小：按现在的样子重新记下靠边的位置，拉出来时回到这里。
        if glide == nil, edgeDrag == nil {
            current.frame = Self.dockedFrame(width: now.width, height: now.height, side: current.side, on: screen)
            let area = visibleAX(screen)
            current.frame.origin.y = min(max(now.minY, area.minY + Self.inset), max(area.minY + Self.inset, area.maxY - now.height - Self.inset))
        }
        unpin()
        let parked = Self.parkedFrame(current.frame, side: current.side, on: screen)
        current.hidden = true
        docked = current
        wlog("slide-over: hide id=\(current.id) reason=\(reason)")
        move(to: parked, from: now, velocity: velocity) { [weak self] in
            guard let self, let d = self.docked, d.id == current.id, d.hidden else { return }
            self.tab.show(for: d.frame, side: d.side, screen: screen)
        }
    }

    /// 从屏幕边滑回来，交到最前面，置顶。
    func show(velocity: CGVector = .zero, reason: String) {
        guard var current = docked, current.hidden else { return }
        guard let now = frameNow(current) else { return }
        tab.hide()
        current.hidden = false
        docked = current
        wlog("slide-over: show id=\(current.id) reason=\(reason)")
        move(to: current.frame, from: now, velocity: velocity) { [weak self] in
            guard let self, let d = self.docked, d.id == current.id, !d.hidden else { return }
            let element = d.element
            DispatchQueue.global(qos: .userInitiated).async {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            NSRunningApplication(processIdentifier: d.pid)?.activate()
            self.pin()
        }
    }

    /// 退出侧拉：窗口留下（收着的先拉回来），不再置顶。
    func exit(reason: String, restoringPosition: Bool = true) {
        guard let current = docked else { return }
        let needsRestore = current.hidden || edgeDrag != nil || (restoringPosition && glide != nil)
        generation &+= 1
        dragWriter?.stopAndWait()
        dragWriter = nil
        edgeDrag = nil
        let previousGlide = glide
        previousGlide?.cancel()
        glide = nil
        tab.hide()
        chrome.hide()
        endChromeGestures()
        mirror?.close()
        mirror = nil
        openingAtHome = false
        if !current.restorePin { unpin() }
        docked = nil
        wlog("slide-over: exit id=\(current.id) reason=\(reason)")
        if needsRestore, let now = frameNow(current) {
            let g = WindowGlide(id: current.id, element: current.element,
                                path: .honoringMotion(from: now, to: current.frame, velocity: .zero), after: previousGlide)
            g.start { [weak self] report in
                if !report.cancelled, abs(report.observed.minX - current.frame.minX) < 8 {
                    SlideOverRecovery.clear(id: current.id)
                    if current.restorePin { self?.restoreOriginalPin(current) }
                }
            }
        } else {
            SlideOverRecovery.clear(id: current.id)
            if current.restorePin { restoreOriginalPin(current) }
        }
    }

    private func restoreOriginalPin(_ d: Docked) {
        owner.pinnedPreviewController.startPreview(targetWindowID: d.id, pid: d.pid, axWindow: d.element) { _ in }
    }

    // MARK: - 标题栏上甩、拖（由 TrackpadGestureController 转过来）

    /// 侧拉的窗口被甩了一下：朝它靠的那一边甩是收起；朝别处甩是退出侧拉，然后照常排。
    /// 返回 true 表示这一下已经处理完。
    func flicked(id: CGWindowID, direction: GestureDirection, velocity: CGVector) -> Bool {
        if titleDragging == id { titleDragging = nil }
        guard let current = docked, current.id == id, !current.hidden else { return false }
        let outward: GestureDirection = current.side == .right ? .right : .left
        if direction == outward {
            hide(velocity: velocity, reason: "flick")
            return true
        }
        if direction == .left || direction == .right,
           let screen = screenForDisplayID(current.display),
           Self.neighborFree(current.side == .left ? .right : .left, screen), let now = frameNow(current) {
            var next = current
            next.side = current.side == .left ? .right : .left
            next.frame = Self.dockedFrame(width: now.width, height: now.height, side: next.side, on: screen)
            docked = next
            unpin()
            move(to: next.frame, from: now, velocity: velocity) { [weak self] in self?.pin() }
            return true
        }
        exit(reason: "flicked away", restoringPosition: false)
        return false
    }

    /// 侧拉的窗口被拖着松手（不是甩）：还在靠边那一带就靠回去；拖到另一边就换边；拖到中间就退出侧拉。
    func dragEnded(id: CGWindowID, moved: Bool = true) {
        if titleDragging == id { titleDragging = nil }
        guard moved else { pin(); return }
        guard var current = docked, current.id == id, !current.hidden,
              let now = frameNow(current), let screen = screenForDisplayID(current.display) else { return }
        if let landedScreen = screenForAXWindow(pos: now.origin, size: now.size), displayID(for: landedScreen) != current.display {
            exit(reason: "dragged to another display", restoringPosition: false)
            return
        }
        let area = visibleAX(screen)
        let center = (now.midX - area.minX) / area.width
        let side: Side?
        switch center {
        case ..<0.3: side = Self.neighborFree(.left, screen) ? .left : nil
        case 0.7...: side = Self.neighborFree(.right, screen) ? .right : nil
        default: side = nil
        }
        guard let side else {
            exit(reason: "dragged to the middle", restoringPosition: false)
            return
        }
        current.side = side
        current.frame = Self.dockedFrame(width: now.width, height: now.height, side: side, on: screen)
        docked = current
        move(to: current.frame, from: now, velocity: .zero) { [weak self] in self?.pin() }
    }

    /// 窗口关掉了，或者 App 退出了。
    func windowGone(_ id: CGWindowID) {
        guard docked?.id == id else { return }
        generation &+= 1
        dragWriter?.stop()
        dragWriter = nil
        edgeDrag = nil
        openingAtHome = false
        unpin()
        tab.hide()
        chrome.hide()
        endChromeGestures()
        mirror?.close()
        mirror = nil
        glide?.cancel()
        docked = nil
        wlog("slide-over: window gone id=\(id)")
    }

    // MARK: - 每张桌面

    /// 窗口在不在眼前这张桌面上（收在屏幕边外也算在，只露几点）。
    private func windowHere(_ d: Docked) -> Bool { windowIsOnScreenNow(d.id) }

    /// 把手或快捷键要拉出来：窗口在这张桌面就拉真窗口，不在就拉它的实时画面。
    func reveal(reason: String) {
        guard let current = docked else { return }
        if windowHere(current) {
            show(reason: reason)
        } else {
            showMirror(reason: reason)
        }
    }

    /// 换了桌面：别的桌面上的实时画面收掉；把手按“窗口在不在这里、收着没有”重新挂。
    private func spaceChanged() {
        dropHint.cancel()
        guard let current = docked else { return }
        if let mirror, mirror.isVisible {
            mirror.close()
            self.mirror = nil
        }
        let here = windowHere(current)
        if openingAtHome, here {
            openingAtHome = false
            if current.hidden { show(reason: "opened from another desktop") } else { pin() }
        }
        refreshTab()
        wlog("slide-over: desktop changed id=\(current.id) here=\(here) hidden=\(current.hidden)")
    }

    private func refreshTab() {
        guard let current = docked,
              let screen = screenForDisplayID(current.display) ?? NSScreen.main else {
            tab.hide()
            return
        }
        if windowHere(current), !current.hidden {
            tab.hide()
        } else {
            tab.show(for: current.frame, side: current.side, screen: screen)
        }
        updateChrome()
    }

    private func showMirror(reason: String, interactive: Bool = false) {
        guard let current = docked, mirror?.isVisible != true,
              let screen = screenForDisplayID(current.display) ?? NSScreen.main else { return }
        if !interactive { tab.hide() }
        let mirror = SlideOverMirror(id: current.id, side: current.side, cornerRadius: chrome.cornerRadius)
        self.mirror = mirror
        mirror.onOpen = { [weak self] in self?.openAtHome() }
        mirror.onDismiss = { [weak self] velocity in self?.dismissMirror(velocity: velocity) }
        mirror.present(at: current.frame, screen: screen, interactive: interactive) { [weak self] ok in
            guard let self, self.mirror === mirror, !ok else { return }
            // 拿不到它的画面：直接回到它所在的桌面。
            self.mirror = nil
            self.openAtHome()
        }
        wlog("slide-over: mirror id=\(current.id) reason=\(reason)")
        showAllDesktopsTipOnce()
    }

    func dismissMirror(velocity: CGFloat) {
        guard let mirror else { return }
        self.mirror = nil
        // 滑走的这一段由完成回调拿着它：否则这里一松手它就被释放，滑不完、把手也挂不回来。
        mirror.slideAway(velocity: velocity) { [weak self] in
            withExtendedLifetime(mirror) {}
            self?.refreshTab()
        }
    }

    /// 点了别的桌面上的实时画面：回到窗口所在的桌面，把真窗口拉出来。
    private func openAtHome() {
        guard let current = docked else { return }
        mirror?.close()
        mirror = nil
        openingAtHome = true
        let request = generation
        let element = current.element
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: current.pid)?.activate()
        wlog("slide-over: open at home id=\(current.id)")
        // 同一张桌面上也开着这个 App 的窗口时，系统不会切过去；那就只把它交到前面。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == request, self.openingAtHome else { return }
                self.openingAtHome = false
                self.refreshTab()
            }
        }
    }

    private func showAllDesktopsTipOnce() {
        let key = "SlideOver.allDesktopsTipShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        owner.quietNotice("想在每张桌面上直接用它：在 Dock 里按住 Control 点它，选项 → 分配给：所有桌面",
                          log: "slide-over: all-desktops tip")
    }

    /// 在标题栏那一带按下：同一个窗口只允许一条位置写入链，正在滑的停在原地。
    /// 只是点一下（地址栏、工具栏）不动边框和置顶；真拖起来才收（dragMoved）。
    func grabbed(_ id: CGWindowID) {
        guard docked?.id == id else { return }
        generation &+= 1
        titleDragging = nil
        guard let caught = glide else { return }
        // 只停不清：它自己报完才清掉，松手后的下一段滑行排在它后面，等它真停手。
        caught.cancel()
        // 滑到一半被抓住：边框不再跟着那条路走，松手后按停下的地方重新挂。
        chrome.hide()
    }

    /// 标题栏上真拖起来了：边框留在原处会和窗口错开，先收掉；置顶也先停。松手后 dragEnded 或 released 挂回来。
    func dragMoved(_ id: CGWindowID) {
        guard docked?.id == id else { return }
        titleDragging = id
        chrome.hide()
        unpin()
    }

    /// 标题栏上这一下结束了，但没有走 dragEnded（拖的是窗口的边在改大小，或者晃了一晃）：边框和置顶挂回来。
    func released(_ id: CGWindowID) {
        if titleDragging == id { titleDragging = nil }
        guard docked?.id == id else { return }
        pin()
    }

    func beginEdgeDrag() {
        guard edgeDrag == nil, let d = docked else { return }
        if !windowHere(d) {
            draggingMirror = true
            showMirror(reason: "edge drag", interactive: true)
            return
        }
        guard let now = frameNow(d) else { return }
        generation &+= 1
        let previous = glide
        previous?.cancel()
        glide = nil
        unpin()
        chrome.hide()
        edgeDrag = (now, now, d.hidden)
        let element = d.element
        dragWriter = SlideOverDragWriter(prepare: { previous?.cancelAndWait() }, apply: { point in
            setAXPosition(element, point)
        })
    }

    func updateEdgeDrag(inward: CGFloat) {
        if draggingMirror { mirror?.edgeProgress(inward: inward); return }
        guard let d = docked, var drag = edgeDrag, let screen = screenForDisplayID(d.display) else { return }
        let parked = Self.parkedFrame(d.frame, side: d.side, on: screen)
        drag.latest.origin.x = SlideOverMotion.position(start: drag.start.minX, inward: inward,
                                                        open: d.frame.minX, parked: parked.minX)
        edgeDrag = drag
        dragWriter?.submit(drag.latest.origin)
    }

    func endEdgeDrag(inwardVelocity: CGFloat, cancelled: Bool) {
        if draggingMirror {
            draggingMirror = false
            tab.hide()
            mirror?.edgeReleased(inwardVelocity: inwardVelocity, cancelled: cancelled)
            return
        }
        guard let d = docked, let drag = edgeDrag, let screen = screenForDisplayID(d.display) else { return }
        let writer = dragWriter
        dragWriter = nil
        edgeDrag = nil
        let request = generation
        let parked = Self.parkedFrame(d.frame, side: d.side, on: screen)
        let velocity = inwardVelocity * (d.side == .right ? -1 : 1)
        let hide = cancelled ? drag.wasHidden : SlideOverMotion.willHide(position: drag.latest.minX,
            velocity: velocity, open: d.frame.minX, parked: parked.minX)
        writer?.stop { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == request, var current = self.docked,
                          current.id == d.id, let now = self.frameNow(current) else { return }
                    current.hidden = hide
                    self.docked = current
                    if !hide { self.tab.hide() }
                    self.move(to: hide ? parked : current.frame, from: now,
                              velocity: CGVector(dx: cancelled ? 0 : velocity, dy: 0)) { [weak self] in
                        self?.refreshTab()
                        if !hide { self?.pin() }
                    }
                }
            }
        }
    }

    private func validateWindow() {
        guard let d = docked else { return }
        guard let info = cgWindowInfo(d.id), (info[kCGWindowOwnerPID as String] as? pid_t) == d.pid else {
            windowGone(d.id)
            return
        }
        if screenForDisplayID(d.display) == nil { screensChanged(); return }
        guard glide == nil, edgeDrag == nil, chromeDrag == nil, resizing == nil else { return }
        // 窗口被最小化、App 被隐藏，或窗口关了进程还留着它：边框、拖动带和把手不能围着一块空处挡别的 App 的点击。
        // 窗口回来了再挂上（置顶要是跟着断了也接上）；标题栏上还按着（正拖着它）时不挂，松手后 dragEnded、released 会挂。
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) == true
        if chrome.isVisible, !onScreen { updateChrome(); return }
        if !chrome.isVisible, onScreen, !d.hidden, titleDragging != d.id, NSEvent.pressedMouseButtons & 1 == 0 { pin(); return }
        // 被人从窗口自己的边上改了大小、挪了位置：边框跟过去。
        if chrome.isVisible, let now = cgWindowBounds(info), let shown = chrome.frameAX,
           abs(now.minX - shown.minX) + abs(now.minY - shown.minY) + abs(now.width - shown.width) + abs(now.height - shown.height) > 1 {
            chrome.place(now)
        }
    }

    func screensChanged() {
        dropHint.cancel()
        guard let d = docked else { return }
        guard let screen = screenForDisplayID(d.display), Self.neighborFree(d.side, screen) else {
            shutdown()
            return
        }
        guard let now = frameNow(d) else { return }
        var next = d
        next.frame = Self.dockedFrame(width: d.frame.width, height: d.frame.height, side: d.side, on: screen)
        docked = next
        move(to: next.hidden ? Self.parkedFrame(next.frame, side: next.side, on: screen) : next.frame,
             from: now, velocity: .zero) { [weak self] in self?.refreshTab() }
    }

    /// 退出进程时不能把真实窗口留在屏幕外。同步仅用于退出/显示器失效，不在手势热路径使用。
    func shutdown() {
        dropHint.cancel()
        guard let d = docked else { return }
        generation &+= 1
        dragWriter?.stopAndWait(); dragWriter = nil; edgeDrag = nil
        glide?.cancelAndWait(); glide = nil
        unpin(); tab.hide(); chrome.hide(); endChromeGestures(); mirror?.close(); mirror = nil; openingAtHome = false
        docked = nil
        let cocoa = cocoaFrame(fromAXPosition: d.frame.origin, size: d.frame.size)
        let target = SlideOverRecovery.clamped(cocoa)
        let destination = axPosition(fromCocoaFrame: target)
        setAXPosition(d.element, destination)
        if let observed = axPosition(d.element), hypot(observed.x - destination.x, observed.y - destination.y) < 8 {
            SlideOverRecovery.clear(id: d.id)
        }
    }

    // MARK: - 几何（纯计算）

    static func side(for frame: CGRect, on screen: NSScreen) -> Side? {
        let area = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
        let preferred: Side = frame.midX < area.midX ? .left : .right
        let other: Side = preferred == .left ? .right : .left
        if neighborFree(preferred, screen) { return preferred }
        if neighborFree(other, screen) { return other }
        return nil
    }

    static func neighborFree(_ side: Side, _ screen: NSScreen) -> Bool {
        TrackpadGestureController.neighbor(of: screen, toward: side == .left ? .left : .right) == nil
    }

    /// 靠边的样子：宽度照原来（夹在 320 点和屏幕四成之间），高度占满可用区域，四周留一点缝。
    static func dockedFrame(width: CGFloat, height: CGFloat? = nil, side: Side, on screen: NSScreen) -> CGRect {
        let area = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
        let w = min(max(width, minimumWidth), max(1, area.width - inset * 2))
        let x = side == .right ? area.maxX - w - inset : area.minX + inset
        let h = min(max(height ?? area.height, 240), area.height - inset * 2)
        return CGRect(x: x, y: area.minY + (area.height - h) / 2, width: w, height: h)
    }

    /// 收起的样子：推到屏幕边外，只留 peek 点。
    static func parkedFrame(_ frame: CGRect, side: Side, on screen: NSScreen) -> CGRect {
        let bounds = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
        let x = side == .right ? bounds.maxX - peek : bounds.minX - frame.width + peek
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }

    // MARK: - 内部

    private func screenAX(_ screen: NSScreen) -> CGRect {
        CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
    }

    private func visibleAX(_ screen: NSScreen) -> CGRect {
        CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
    }

    /// 窗口此刻在哪：问 WindowServer，不经过那个 App（慢 App 一次辅助功能调用能卡几十到几百毫秒）。
    private func frameNow(_ d: Docked) -> CGRect? {
        guard let info = cgWindowInfo(d.id), let bounds = cgWindowBounds(info) else {
            windowGone(d.id)
            return nil
        }
        return bounds
    }

    private func move(to target: CGRect, from current: CGRect, velocity: CGVector, done: @escaping () -> Void) {
        guard let d = docked else { return }
        if let writer = dragWriter {
            generation &+= 1
            let request = generation
            dragWriter = nil; edgeDrag = nil
            writer.stop { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self, self.generation == request, let now = self.frameNow(d) else { return }
                    self.move(to: target, from: now, velocity: velocity, done: done)
                } }
            }
            return
        }
        generation &+= 1
        let request = generation
        let g = WindowGlide(id: d.id, element: d.element, path: .honoringMotion(from: current, to: target, velocity: velocity),
                            after: glide)
        glide = g
        // 边框和窗口走同一条路：拉出来时从屏幕边一起滑进来，收起时一起滑出去。
        if (!d.hidden || chrome.isVisible) && windowHere(d) { chrome.follow(g.path, side: d.side) }
        g.start { [weak self] report in
            guard let self else { return }
            if self.glide === g { self.glide = nil }
            wlog(String(format: "slide-over: glide id=%d took=%.0fms frames=%d%@", d.id, report.elapsed * 1000, report.frames,
                        report.cancelled ? " cancelled" : ""))
            guard !report.cancelled, self.generation == request, var current = self.docked, current.id == d.id else { return }
            if abs(report.observed.minX - target.minX) > 12 || abs(report.observed.minY - target.minY) > 12 {
                let cocoa = cocoaFrame(fromAXPosition: report.observed.origin, size: report.observed.size)
                current.hidden = !NSScreen.screens.contains { cocoa.intersection($0.visibleFrame).width > 64 }
                if !current.hidden { current.frame = report.observed }
                self.docked = current
                self.refreshTab()
                self.owner.quietNotice("窗口没有跟上操作，请再试一次", log: "slide-over: window rejected landing")
                return
            }
            if !current.hidden { current.frame = report.observed; self.docked = current }
            done()
            self.updateChrome()
        }
    }

    /// 置顶还在启动时就被收起（连按两下快捷键），那次启动会以“目标变了”失败，紧接着的这次请求也会跟着它一起失败：
    /// 窗口还拉出着的话，稍等再试，最多两次。
    private func pin(attempt: Int = 0) {
        if attempt == 0 { updateChrome() }
        guard let d = docked, !d.hidden, edgeDrag == nil, chromeDrag == nil, resizing == nil,
              !owner.pinnedPreviewController.isPreviewing(id: d.id) else { return }
        let request = generation
        owner.pinnedPreviewController.startPreview(targetWindowID: d.id, pid: d.pid, axWindow: d.element) { [weak self] result in
            guard let self, self.generation == request, self.docked?.id == d.id, self.docked?.hidden == false else { return }
            guard case .failure(let error) = result else { return }
            wlog("slide-over: pin failed \(error) attempt=\(attempt)")
            guard case .targetChanged = error, attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    guard self.generation == request, let now = self.docked, now.id == d.id, !now.hidden else { return }
                    self.pin(attempt: attempt + 1)
                }
            }
        }
    }

    private func unpin() {
        guard let d = docked else { return }
        owner.pinnedPreviewController.stopPreviewFromMenu(id: d.id)
    }

    // MARK: - 边框和把手

    /// 窗口拉出来、停稳、在眼前这张桌面上：挂上边框；否则收掉。正在拖边框或把手时不动它。
    private func updateChrome() {
        if chromeDrag != nil || resizing != nil { return }
        guard let d = docked, !d.hidden, glide == nil, edgeDrag == nil, windowHere(d),
              let info = cgWindowInfo(d.id), let now = cgWindowBounds(info) else {
            chrome.hide()
            return
        }
        chrome.show(around: now, side: d.side)
    }

    /// 探针用：拖一下把手（按下、挪、松开）。
    func resizeForProbe(by delta: CGVector) { beginResize(); updateResize(delta); endResize() }

    private func endChromeGestures() {
        chromeDrag?.writer.stop(); chromeDrag = nil
        resizing?.writer.stop(); resizing = nil
    }

    /// 按住边框拖：窗口跟着手走（写位置只留最新的一个）。
    private func beginChromeDrag() {
        guard chromeDrag == nil, resizing == nil, let d = docked, !d.hidden, let now = frameNow(d) else { return }
        generation &+= 1
        let previous = glide
        previous?.cancel()
        glide = nil
        // 边框可能还在跟着刚才那段滑行走：停下，从这里起由手摆。
        chrome.stopFollowing()
        unpin()
        let element = d.element
        owner.notch.coachUsed(.slideOverHandle)
        chromeDrag = (now, LatestValueWriter<CGPoint>(prepare: { previous?.cancelAndWait() }, apply: { setAXPosition(element, $0) }))
        wlog("slide-over: border drag begins id=\(d.id)")
    }

    private func updateChromeDrag(_ delta: CGVector) {
        guard let drag = chromeDrag else { return }
        let frame = drag.start.offsetBy(dx: delta.dx, dy: -delta.dy)
        drag.writer.submit(frame.origin)
        chrome.place(frame)
    }

    /// 松手：甩出去就和在标题栏上甩一样（朝靠的那边是收起，朝另一边是换边）；不是甩就按落在哪决定靠回去、换边还是退出。
    private func endChromeDrag(velocity: CGVector) {
        guard let drag = chromeDrag, let d = docked else { return }
        chromeDrag = nil
        let request = generation
        drag.writer.stop { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == request, self.docked?.id == d.id else { return }
                    let ax = CGVector(dx: velocity.dx, dy: -velocity.dy)
                    if abs(ax.dx) > 800, abs(ax.dx) > abs(ax.dy) * 1.5 {
                        _ = self.flicked(id: d.id, direction: ax.dx > 0 ? .right : .left, velocity: ax)
                        return
                    }
                    self.dragEnded(id: d.id)
                }
            }
        }
    }

    /// 按住角上的把手：改宽和高，靠屏幕边的那一边和顶边不动。
    private func beginResize() {
        guard resizing == nil, chromeDrag == nil, let d = docked, !d.hidden, let now = frameNow(d),
              let screen = screenForDisplayID(d.display) else { return }
        generation &+= 1
        let previous = glide
        previous?.cancel()
        glide = nil
        chrome.stopFollowing()
        unpin()
        owner.notch.coachUsed(.slideOverHandle)
        let element = d.element
        let side = d.side
        let last = ResizeMemory(now)
        let writer = LatestValueWriter<CGRect>(prepare: { previous?.cancelAndWait() }, apply: { [weak self] frame in
            // 变大先挪再改大小，变小先改大小再挪：中间那一下不伸出屏幕边。
            let growing = frame.width > last.frame.width || frame.height > last.frame.height
            var at = last.frame.origin
            if growing, abs(frame.minX - at.x) > 0.5 || abs(frame.minY - at.y) > 0.5 {
                setAXPosition(element, frame.origin)
                at = frame.origin
            }
            let began = CACurrentMediaTime()
            _ = setAXSize(element, frame.size)
            let sized = CACurrentMediaTime()
            // App 自己有最小、最大尺寸（或按字符格改）时会夹住：按它实际接受的大小摆，靠屏幕边的那一边不动。
            // 读回实际尺寸：改得快的 App 每帧读（几乎不花时间）；慢的（改一次超过 12 毫秒，和 WindowGlide 同一条线）
            // 读一次也要几十毫秒，只在夹住时每帧读，平时隔 50 毫秒读一次，松手时 endResize 再对一次。
            var size = frame.size
            if last.clamped || sized - began < 0.012 || sized - last.checkedAt >= 0.05 {
                size = axSize(element) ?? frame.size
                last.checkedAt = sized
            }
            let placed = CGRect(x: side == .right ? frame.maxX - size.width : frame.minX, y: frame.minY,
                                width: size.width, height: size.height)
            if abs(placed.minX - at.x) > 0.5 || abs(placed.minY - at.y) > 0.5 { setAXPosition(element, placed.origin) }
            last.frame = placed
            // 夹住了（或刚松开）：告诉主线程，边框改按窗口实际的样子摆。
            let clamped = abs(size.width - frame.width) > 1 || abs(size.height - frame.height) > 1
            guard clamped || last.clamped else { return }
            last.clamped = clamped
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.resizeLanded(placed, clamped: clamped, memory: last) }
            }
        })
        resizing = (now, visibleAX(screen), last, writer, false)
        wlog("slide-over: resize begins id=\(d.id) from=\(now)")
    }

    private func updateResize(_ delta: CGVector) {
        guard let r = resizing, let d = docked else { return }
        let s = r.start
        let widest = max(Self.minimumWidth, r.area.width - Self.inset * 2)
        let width = min(max(d.side == .right ? s.width - delta.dx : s.width + delta.dx, Self.minimumWidth), widest)
        let tallest = max(240, r.area.maxY - Self.inset - s.minY)
        let height = min(max(s.height - delta.dy, 240), tallest)
        let frame = CGRect(x: d.side == .right ? s.maxX - width : s.minX, y: s.minY, width: width, height: height)
        r.writer.submit(frame)
        if !r.clamped { chrome.place(frame) }
    }

    /// 写入那条队列报回来：App 没按要的尺寸来（夹住了），边框贴着窗口实际的样子，不跟着手跑到窗口外；又按要的来了就交还给手。
    private func resizeLanded(_ frame: CGRect, clamped: Bool, memory: ResizeMemory) {
        guard resizing?.memory === memory else { return }
        resizing?.clamped = clamped
        chrome.place(frame)
    }

    private func endResize() {
        guard let r = resizing, let d = docked else { return }
        resizing = nil
        let request = generation
        let element = d.element
        let side = d.side
        let edge = side == .right ? r.start.maxX : r.start.minX
        let memory = r.memory
        r.writer.stop { [weak self] in
            // 在写入那条队列上，前面的写入都已返回：只读一次窗口实际停下的样子（应用自己可能有最小、最大尺寸）。
            // 这里不写：松手后马上收起、拖边框时，这一下会和新的滑行抢窗口。
            var landed = memory.frame
            if let position = axPosition(element), let size = axSize(element) { landed = CGRect(origin: position, size: size) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == request, var current = self.docked, current.id == d.id,
                          !current.hidden, self.frameNow(current) != nil else { return }
                    // 靠屏幕边的那一边要是被挤开了，滑回原处（不让窗口伸出屏幕边）；走滑行那条链，之后的挪动会等它。
                    var target = landed
                    target.origin.x = side == .right ? edge - landed.width : edge
                    current.frame = target
                    self.docked = current
                    // 崩溃后的恢复也按新的大小把窗口夹回屏幕里。
                    _ = SlideOverRecovery.record(id: current.id, pid: current.pid, frame: target)
                    wlog("slide-over: resized id=\(d.id) to=\(target) landed=\(landed)")
                    if abs(landed.minX - target.minX) > 1 {
                        self.move(to: target, from: landed, velocity: .zero) { [weak self] in self?.pin() }
                    } else {
                        self.pin()
                    }
                }
            }
        }
    }
}

/// 改大小时窗口上一次实际停下的外框、那一下 App 有没有夹住尺寸、上次读回尺寸的时刻：只在写入那条队列上读写。
private final class ResizeMemory: @unchecked Sendable {
    var frame: CGRect
    var clamped = false
    var checkedAt = -Double.infinity
    init(_ frame: CGRect) { self.frame = frame }
}

/// 收起后留在屏幕边上的把手：贴着屏幕边的一小片玻璃，中间一个朝里的箭头（iPadOS 的样子）。
/// 点一下、或者在上面往里划，窗口就拉出来。
@MainActor
final class SlideOverTab {
    var onReveal: (() -> Void)?
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat, Bool) -> Void)?
    private var panel: NSPanel?
    static let size = CGSize(width: 16, height: 76)

    /// frame：窗口靠边时的外框（AX 坐标）；把手挂在那一边、对着窗口的中间。
    func show(for frame: CGRect, side: SlideOverController.Side, screen: NSScreen) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let edgeX = side == .right ? screen.frame.maxX - Self.size.width : screen.frame.minX
        let cocoa = cocoaFrame(fromAXPosition: frame.origin, size: frame.size)
        let y = min(max(cocoa.midY - Self.size.height / 2, screen.visibleFrame.minY + 8),
                    screen.visibleFrame.maxY - Self.size.height - 8)
        panel.setFrame(NSRect(x: edgeX, y: y, width: Self.size.width, height: Self.size.height), display: true)
        (panel.contentView as? SlideOverTabView)?.side = side
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // 每张桌面都挂（全屏 App 的桌面上也挂）；哪张桌面该不该露出来，由换桌面时重新判断。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.hidesOnDeactivate = false
        let view = SlideOverTabView(frame: NSRect(origin: .zero, size: Self.size))
        view.onReveal = { [weak self] in self?.onReveal?() }
        view.onBegin = { [weak self] in self?.onBegin?() }
        view.onDrag = { [weak self] in self?.onDrag?($0) }
        view.onEnd = { [weak self] in self?.onEnd?($0, $1) }
        panel.contentView = view
        return panel
    }
}

final class SlideOverTabView: NSView {
    var onReveal: (() -> Void)?
    var side: SlideOverController.Side = .right { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat, Bool) -> Void)?
    private var down: CGPoint?
    private var samples: [FlickSample] = []
    private var scrolling = false
    private var displacement: CGFloat = 0
    private var dragged = false
    private var sign: CGFloat { side == .right ? -1 : 1 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("拉出侧拉的窗口")
    }
    override func accessibilityPerformPress() -> Bool { onReveal?(); return true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation
        dragged = false
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let now = NSEvent.mouseLocation
        if !dragged { dragged = true; onBegin?() }
        sample(now, event.timestamp)
        onDrag?((now.x - down.x) * sign)
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        if dragged { onEnd?(speed(at: event.timestamp) * sign, false) }
        else { onReveal?() }
        dragged = false
    }
    override func cancelOperation(_ sender: Any?) {
        if dragged || scrolling { onEnd?(0, true) }
        down = nil; dragged = false; scrolling = false
    }
    private func sample(_ point: CGPoint, _ time: TimeInterval) {
        samples.append(FlickSample(time: time, point: point))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
    }
    private func speed(at time: TimeInterval) -> CGFloat {
        guard let last = samples.last, time - last.time < 0.07 else { return 0 }
        return FlickRelease.measure(samples, lift: time)?.velocity.dx ?? 0
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if !event.hasPreciseScrollingDeltas || event.phase.isEmpty {
            if event.scrollingDeltaX * sign > 0 { onReveal?() }
            return
        }
        if event.phase == .began {
            scrolling = true; displacement = 0
            samples = [FlickSample(time: event.timestamp, point: .zero)]
            onBegin?()
        }
        guard scrolling else { return }
        displacement += event.scrollingDeltaX
        sample(CGPoint(x: displacement, y: 0), event.timestamp)
        onDrag?(displacement * sign)
        if event.phase == .ended || event.phase == .cancelled {
            onEnd?(speed(at: event.timestamp) * sign, event.phase == .cancelled)
            scrolling = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        SlideOverEdgeTab.draw(in: bounds, side: side, highlighted: hovering, dark: dark)
    }
}

/// 别的桌面上的侧拉：窗口本身挪不过来（见文件开头），就把它的实时画面从屏幕边滑进来，大小和它靠边时一样。
/// 可以看；点一下回到它所在的桌面接着用；往边上推或甩，收回去。画面和置顶用的是同一种实时画面（每秒 30 帧，
/// 红绿灯上的录屏标记换回干净底片）。
/// 面板从靠边的位置一直开到屏幕边，本身不动；滑的是里面那一层（Core Animation 的弹簧，渲染进程播，
/// 主线程忙也不掉帧）。手拖时这一层一比一跟着手。
@MainActor
final class SlideOverMirror {
    var onOpen: (() -> Void)?
    /// 收回去：参数是往屏幕边外的速度（点/秒）。
    var onDismiss: ((CGFloat) -> Void)?
    let id: CGWindowID
    let side: SlideOverController.Side
    private let panel: NSPanel
    private let capture = WindowStreamCapture()
    private let content: SlideOverMirrorView
    /// 滑出去时那一层要平移多远（点，正数朝屏幕边外）。
    private var offscreenShift: CGFloat = 0
    private var closed = false
    private var docked: NSRect = .zero

    var isVisible: Bool { panel.isVisible && !closed }
    var deliveredFrames: UInt64 { capture.deliveredFrameCount }
    /// 画面此刻在屏幕上的外框（Cocoa 坐标，含滑动中的平移）。
    var frame: NSRect {
        let shift = content.currentShift()
        return docked.offsetBy(dx: side == .right ? shift : -shift, dy: 0)
    }

    init(id: CGWindowID, side: SlideOverController.Side, cornerRadius: CGFloat = SlideOverChrome.defaultCornerRadius) {
        self.id = id
        self.side = side
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        content = SlideOverMirrorView(frame: panel.contentLayoutRect, videoLayer: capture.videoLayer)
        panel.contentView = content
        content.side = side
        content.cornerRadius = cornerRadius
        content.onClick = { [weak self] in self?.onOpen?() }
        content.onDrag = { [weak self] dx in self?.dragged(by: dx) }
        content.onRelease = { [weak self] outward, speed in self?.released(outward: outward, speed: speed) }
    }

    /// frameAX：窗口靠边时的外框（AX 坐标）。completion(false)：拿不到画面。
    func present(at frameAX: CGRect, screen: NSScreen, interactive: Bool = false, completion: @escaping (Bool) -> Void) {
        docked = cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size)
        // 面板从靠边的位置一直开到屏幕边：画面从屏幕边滑进来，被面板边裁掉的正好是屏幕外的部分。
        // 靠里那边和上下多留出玻璃边框和阴影的地方。
        let pad = SlideOverMirrorView.pad
        let area = side == .right
            ? NSRect(x: docked.minX - pad, y: docked.minY - pad, width: screen.frame.maxX - docked.minX + pad, height: docked.height + pad * 2)
            : NSRect(x: screen.frame.minX, y: docked.minY - pad, width: docked.maxX - screen.frame.minX + pad, height: docked.height + pad * 2)
        offscreenShift = area.width
        panel.setFrame(area, display: false)
        content.layoutPicture(size: docked.size, anchoredRight: side == .left)
        content.setShift(offscreenShift)
        panel.orderFrontRegardless()
        // 先滑进来（背景和 App 图标垫着），画面到了就接上：不让人等开流的那一两百毫秒。
        if !interactive { content.animateShift(to: 0, velocity: 0, bounce: 0.12, done: nil) }
        let id = self.id
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        Task { @MainActor [weak self] in
            let shareable: SCShareableContent?
            if let cached = await ShareableContentCache.shared.content(requiring: id) {
                shareable = cached
            } else {
                shareable = try? await ShareableContentLoader.current()
            }
            guard let self, !self.closed else { return }
            guard let window = shareable?.windows.first(where: { $0.windowID == id }) else {
                self.close()
                completion(false)
                return
            }
            self.content.appIcon = window.owningApplication.flatMap {
                NSRunningApplication(processIdentifier: $0.processID)?.icon
            }
            let display = shareable?.displays.first { $0.displayID == screenID }
            self.capture.takesCleanPlate = true
            self.capture.isInteractive = true
            do {
                try await self.capture.start(window: window, display: display)
                guard !self.closed else { self.capture.stop(); return }
                completion(true)
            } catch {
                wlog("slide-over: mirror capture failed id=\(id) \(error.localizedDescription)")
                self.close()
                completion(false)
            }
        }
    }

    /// 带着速度滑回屏幕边外，然后收掉。velocity：往边外的速度（点/秒）。
    func slideAway(velocity: CGFloat, done: @escaping () -> Void) {
        content.animateShift(to: offscreenShift, velocity: velocity, bounce: 0, done: { [weak self] in
            self?.close()
            done()
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        capture.stop()
        panel.orderOut(nil)
    }

    func edgeProgress(inward: CGFloat) {
        let value = offscreenShift - inward
        content.setShift(value >= 0 ? min(value, offscreenShift) : -CGFloat(FluidMotion.rubberBand(Double(-value), limit: 40)))
    }

    func edgeReleased(inwardVelocity: CGFloat, cancelled: Bool) {
        if cancelled { onDismiss?(0) }
        else { released(outward: content.currentShift(), speed: -inwardVelocity) }
    }

    // MARK: - 手拖：一比一跟着手，往屏幕中间拖有阻力

    private var dragStart: CGFloat?

    private func dragged(by dx: CGFloat) {
        let start = dragStart ?? content.currentShift()
        dragStart = start
        let shift = start + dx * (side == .right ? 1 : -1)
        // 往屏幕中间拖：橡皮筋，越拖越沉，但不撞墙（WWDC18）。
        content.setShift(shift >= 0 ? shift : -CGFloat(FluidMotion.rubberBand(Double(-shift), limit: 40)))
    }

    /// 松手：按惯性推算会停在哪（WWDC18，r = 0.998 像普通滚动），过了一半就推回屏幕边，不然弹回来。
    private func released(outward: CGFloat, speed: CGFloat) {
        dragStart = nil
        let projected = content.currentShift() + CGFloat(FluidMotion.projection(velocity: Double(speed)))
        if projected > docked.width / 2 {
            onDismiss?(max(speed, 0))
        } else {
            content.animateShift(to: 0, velocity: speed, bounce: 0.12, done: nil)
        }
    }
}

/// 实时画面那一层（圆角、底色、App 图标、实时画面、说明）+ 接住点击和横向拖动。
final class SlideOverMirrorView: NSView {
    var onClick: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    /// (往边外的位移, 往边外的离手速度 点/秒)
    var onRelease: ((CGFloat, CGFloat) -> Void)?
    var side: SlideOverController.Side = .right
    var appIcon: NSImage? {
        didSet { iconLayer.contents = appIcon?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    }
    /// 画面外面留给玻璃边框和阴影的宽度。
    static let pad = SlideOverChrome.thickness + 26
    var cornerRadius: CGFloat = SlideOverChrome.defaultCornerRadius {
        didSet { picture.cornerRadius = cornerRadius; ring.innerRadius = cornerRadius }
    }
    private let videoLayer: AVSampleBufferDisplayLayer
    /// 滑动的是这一层：玻璃边框和画面一起走。
    private let holder = CALayer()
    private let ring = SlideOverRingLayer()
    private let picture = CALayer()
    private let iconLayer = CALayer()
    private let hintLayer = CATextLayer()
    private var downAt: NSPoint?
    private var samples: [FlickSample] = []
    /// 往屏幕边外平移了多少（点）。
    private var shift: CGFloat = 0

    init(frame: NSRect, videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        picture.backgroundColor = NSColor.windowBackgroundColor.cgColor
        picture.cornerRadius = cornerRadius
        picture.masksToBounds = true
        layer?.addSublayer(holder)
        ring.innerRadius = cornerRadius
        ring.dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        holder.addSublayer(ring)
        holder.addSublayer(picture)
        iconLayer.contentsGravity = .resizeAspect
        picture.addSublayer(iconLayer)
        videoLayer.videoGravity = .resizeAspect
        picture.addSublayer(videoLayer)
        hintLayer.string = "点一下，回到它所在的桌面"
        hintLayer.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hintLayer.fontSize = 12
        hintLayer.foregroundColor = NSColor.white.cgColor
        hintLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        hintLayer.cornerRadius = 10
        hintLayer.alignmentMode = .center
        hintLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        picture.addSublayer(hintLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.3
            self?.hintLayer.opacity = 0
            self?.hintLayer.add(fade, forKey: "fade")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 画面大小（靠边时的窗口大小）；anchoredRight：靠左边时面板从屏幕左边开到画面右沿，画面贴面板右边。
    func layoutPicture(size: NSSize, anchoredRight: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pad = Self.pad
        holder.frame = bounds
        let x = anchoredRight ? bounds.width - size.width - pad : pad
        picture.frame = NSRect(x: x, y: pad, width: size.width, height: size.height)
        ring.frame = picture.frame.insetBy(dx: -pad, dy: -pad)
        iconLayer.frame = NSRect(x: size.width / 2 - 32, y: size.height / 2 - 32, width: 64, height: 64)
        videoLayer.frame = picture.bounds
        let width: CGFloat = 170
        hintLayer.frame = NSRect(x: (size.width - width) / 2, y: 14, width: width, height: 20)
        CATransaction.commit()
    }

    func currentShift() -> CGFloat {
        let presented = (holder.presentation() ?? holder).value(forKeyPath: "transform.translation.x") as? CGFloat ?? 0
        return side == .right ? presented : -presented
    }

    /// 不带动画地平移（手拖时一比一）。
    func setShift(_ value: CGFloat) {
        shift = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.removeAnimation(forKey: "slide")
        holder.setValue(side == .right ? value : -value, forKeyPath: "transform.translation.x")
        CATransaction.commit()
    }

    /// 弹簧平移到 value；velocity：往边外的速度（点/秒）。
    func animateShift(to value: CGFloat, velocity: CGFloat, bounce: CGFloat, done: (() -> Void)?) {
        let from = currentShift()
        let distance = value - from
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(done)
        let reduced = Motion.reduced
        let spring = CASpringAnimation(perceptualDuration: reduced ? 0.3 : 0.42, bounce: reduced ? 0 : bounce)
        spring.keyPath = "transform.translation.x"
        let sign: CGFloat = side == .right ? 1 : -1
        spring.fromValue = from * sign
        spring.toValue = value * sign
        spring.initialVelocity = !reduced && abs(distance) > 1 ? max(-40, min(40, velocity / distance)) : 0
        spring.duration = spring.settlingDuration
        shift = value
        holder.setValue(value * sign, forKeyPath: "transform.translation.x")
        holder.add(spring, forKey: "slide")
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let now = NSEvent.mouseLocation
        samples.append(FlickSample(time: event.timestamp, point: now))
        onDrag?(now.x - downAt.x)
    }

    override func mouseUp(with event: NSEvent) {
        guard let downAt else { return }
        self.downAt = nil
        let now = NSEvent.mouseLocation
        let dx = now.x - downAt.x
        if abs(dx) < 4, abs(now.y - downAt.y) < 4 {
            onClick?()
            return
        }
        let outward: CGFloat = side == .right ? 1 : -1
        // 离手速度照实给（放慢了再松手，速度自然就小），由推算决定去留。
        let release = FlickRelease.measure(samples, lift: event.timestamp)
        let speed = (release?.velocity.dx ?? 0) * outward
        onRelease?(dx * outward, speed)
    }
}
