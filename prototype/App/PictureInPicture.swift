// 画中画（iPadOS 的 Picture in Picture，但对任意窗口）：窗口缩成一张实时画面浮在屏幕角落，原窗口让开。
// 手感照 iPad：拖着一比一跟手，松手按速度甩到最近的角；推出屏幕左右边就藏起来，边上留一小片带箭头的玻璃，
// 往里拉或点一下回来；捏合、⌘ 加滚轮在三档大小之间换。多出来的：
// - 任意窗口都行（会议、聊天、终端、构建日志、表格、文档），不只是视频和它认得的文件；
// - 只看窗口里的一块：框出播放器、发言人、终端最后几行，只截这一块；
// - 滚轮直接滚原窗口；上一页、下一页也发给原窗口（按一屏滚），不切前台；播放 / 暂停走系统媒体键；
// - 可以同时开几个，同一个角落排成一列；跟着到每张桌面、盖在全屏 App 上；
// - 藏起来时停掉截取，指针在上面时每秒 30 帧，平时 15 帧。
// 双击或点“回到原处”，画面放大回原来的位置，真窗口回来（位置和大小都回来）并交到前面。原窗口让开时推到屏幕边外
// 只留两点（那一边挨着别的屏幕就换一边，两边都挨着就不进）；进之前先写恢复记录（和侧拉同一个），本应用异常退出后
// 下次启动会把它放回来。显示器拔掉了，那块屏上的画中画就回到原处，窗口挪进还在的屏幕。
// 算法（大小、吸附、藏起来、只看一块的换算、让开的位置）见 Core/PiPLayout.swift。

import Cocoa
import ScreenCaptureKit

@MainActor
final class PictureInPictureController {
    unowned let owner: AppDelegate
    let dropHint = PiPDropHint()
    private var sessions: [CGWindowID: PiPSession] = [:]
    /// 正在回到原处的（画面在放大、真窗口还没放好）：这段时间不接新的画中画，放好了再删恢复记录。
    private var exiting: [CGWindowID: PiPSession] = [:]
    /// 进画中画的先后：同一个角落里先来的离角近。
    private var order: [CGWindowID] = []
    private var maintenance: Timer?

    init(owner: AppDelegate) { self.owner = owner }

    var activeIDs: [CGWindowID] { order }
    func isInPictureInPicture(_ id: CGWindowID) -> Bool { sessions[id] != nil || exiting[id] != nil }
    var menuTitle: String { "画中画当前窗口" }

    // MARK: - 探针用

    func panelFrameForProbe(_ id: CGWindowID) -> NSRect? { sessions[id].map { $0.panel.frame } }
    func isStashedForProbe(_ id: CGWindowID) -> Bool { sessions[id]?.stashed != nil }
    func framesForProbe(_ id: CGWindowID) -> UInt64 { sessions[id]?.capture.pixelFrameCount ?? 0 }
    func cornerForProbe(_ id: CGWindowID) -> PiPCorner? { sessions[id]?.corner }
    func levelForProbe(_ id: CGWindowID) -> PiPSizeLevel? { sessions[id]?.level }
    func cropForProbe(_ id: CGWindowID) -> CGRect? { sessions[id]?.crop }
    func tabFrameForProbe(_ id: CGWindowID) -> NSRect? { sessions[id]?.tab?.frame }
    func releaseForProbe(_ id: CGWindowID, at frame: NSRect, velocity: CGVector) {
        guard let s = sessions[id] else { return }
        s.panel.setFrame(frame, display: false)
        released(s, velocity: velocity)
    }
    func revealForProbe(_ id: CGWindowID) { sessions[id].map { reveal($0) } }
    func resizeForProbe(_ id: CGWindowID, bigger: Bool) { sessions[id].map { step($0, bigger: bigger) } }
    func cropForProbe(_ id: CGWindowID, selection: CGRect) { sessions[id].map { applyCrop($0, selection: selection) } }
    func pageForProbe(_ id: CGWindowID, down: Bool) { sessions[id].map { page($0, down: down) } }

    // MARK: - 进出

    /// 快捷键、菜单：最前面那扇窗进画中画；它已经在画中画里就回到原处。
    func toggleCurrentWindow() {
        DispatchQueue.global(qos: .userInitiated).async {
            let win = focusedWindow()
            let id = win.flatMap { windowID(of: $0) }
            var pid: pid_t = 0
            if let win { AXUIElementGetPid(win, &pid) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    guard let win, let id else {
                        self.owner.notch.announce("没有可以放进画中画的窗口", tone: .problem)
                        return
                    }
                    if self.sessions[id] != nil { self.exit(id, activate: true) } else { self.enter(win, id: id, pid: pid) }
                }
            }
        }
    }

    /// 放进画中画。corner：从哪个角落拖进来的就放哪；nil 时放在离窗口最近的角。
    /// home：回到原处回哪（AX 坐标）。拖着标题栏进来时传按下那一刻的位置（松手时窗口停在角落、大半在屏幕外）；
    /// nil 就是窗口现在的位置。画面照样从窗口现在的位置缩下去。
    func enter(_ win: AXUIElement, id: CGWindowID, pid: pid_t, corner preferred: PiPCorner? = nil, on targetScreen: NSScreen? = nil,
               home: CGRect? = nil) {
        dropHint.cancel()
        // 正在回到原处的那扇不接：窗口还停在屏幕外，这时进会把让开的位置记成原处。
        guard sessions[id] == nil, exiting[id] == nil, let info = cgWindowInfo(id), let frameAX = cgWindowBounds(info),
              (info[kCGWindowOwnerPID as String] as? pid_t) == pid, pid != getpid(),
              let screen = targetScreen ?? screenForAXWindow(pos: frameAX.origin, size: frameAX.size) else { return }
        guard owner.shaded[id] == nil else {
            owner.notch.announce("先展开这扇窗，再放进画中画", tone: .problem)
            return
        }
        var original = home ?? frameAX
        if owner.slideOver.isSlideOver(id) {
            // 收在屏幕边外的侧拉窗口：它现在的位置不是原处，退出侧拉时滑回来的那一段还会和让开抢位置。
            guard !owner.slideOver.isHidden else {
                owner.notch.announce("先拉出侧拉的窗口，再放进画中画", tone: .problem)
                return
            }
            // 靠边那一格就是它的原处（滑到一半时读到的位置不算）。
            if home == nil, let docked = owner.slideOver.dockedFrame { original = docked }
        }
        // 让开要推到屏幕左右边外；两边都挨着别的屏幕时，推到哪边都会整扇露在旁边那块屏上。
        guard parkedFrame(CGRect(origin: original.origin, size: frameAX.size), on: screen) != nil else {
            owner.notch.announce("这扇窗放不进画中画", detail: "两边都挨着别的屏幕", tone: .problem)
            putBackDropped(win, home: home)
            return
        }
        if owner.slideOver.isSlideOver(id) { owner.slideOver.exit(reason: "picture in picture", restoringPosition: false) }
        if owner.pinnedPreviewController.isPreviewing(id: id) { owner.pinnedPreviewController.stopPreviewFromMenu(id: id) }
        guard SlideOverRecovery.record(id: id, pid: pid, frame: original) else {
            owner.notch.announce("暂时不能放进画中画，请再试一次", tone: .problem)
            putBackDropped(win, home: home)
            return
        }
        let area = screen.visibleFrame
        let windowCocoa = cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size)
        let corner = preferred ?? PiPLayout.corner(nearest: CGPoint(x: windowCocoa.midX, y: windowCocoa.midY), area: area)
        let session = PiPSession(id: id, pid: pid, element: win, original: original, entered: frameAX, windowSize: frameAX.size,
                                 corner: corner, displayID: displayID(for: screen))
        sessions[id] = session
        order.append(id)
        wireUp(session)
        owner.notch.coachUsed(.pip)
        wlog("pip: enter id=\(id) corner=\(corner) frame=\(frameAX) home=\(original)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let content = try? await ShareableContentLoader.current()
            guard self.sessions[id] === session,
                  let window = content?.windows.first(where: { $0.windowID == id }) else {
                self.abandon(session, reason: "no shareable window")
                return
            }
            let display = content?.displays.first { $0.displayID == session.displayID }
            let target = self.frame(for: session, on: screen)
            session.capture.setPictureInPictureOutput(pixels: self.pixels(target.size, screen: screen), source: nil)
            do {
                try await session.capture.start(window: window, display: display)
            } catch {
                self.abandon(session, reason: "capture \(error.localizedDescription)")
                return
            }
            // 等第一帧再让窗口让开：画面从窗口原来的位置缩到角落，中间不露空。
            for _ in 0..<40 where session.capture.pixelFrameCount == 0 {
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
            // 等的时候已经回到原处或收掉了：流可能比那边的停止晚开起来，这里再停一次。
            guard self.sessions[id] === session else { session.capture.stop(); return }
            // 进来到现在显示器变了、两边都挨着别的屏幕了：不让开，画中画收掉。
            guard self.park(session, screen: screen) else {
                self.abandon(session, reason: "nowhere to step aside")
                return
            }
            session.panel.setFrame(windowCocoa, display: false)
            session.panel.alphaValue = 1
            session.panel.orderFrontRegardless()
            self.animate(session.panel, to: target, velocity: .zero)
            self.ensureMaintenance()
        }
    }

    /// 回到原处：画面放大回窗口原来的位置，真窗口回来（位置和大小）。activate：交到前面（双击、“回到原处”）；
    /// 点 × 关掉时不抢前台，只把窗口放回原处。
    func exit(_ id: CGWindowID, activate: Bool) {
        guard let s = sessions[id] else { return }
        sessions[id] = nil
        exiting[id] = s
        order.removeAll { $0 == id }
        s.animation?.invalidate()
        s.panel.ignoresMouseEvents = true
        s.tab?.orderOut(nil)
        let home = homeFrame(s)
        if s.stashed != nil { s.panel.alphaValue = 0 }
        animate(s.panel, to: cocoaFrame(fromAXPosition: home.origin, size: home.size), velocity: .zero,
                duration: Motion.reduced ? 0.12 : 0.28) { [weak self] in
            self?.putBack(s, to: home, activate: activate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                s.capture.stop()
                s.panel.orderOut(nil)
                self?.restack(corner: s.corner)
            }
        }
        wlog("pip: exit id=\(id) activate=\(activate)")
        if sessions.isEmpty { maintenance?.invalidate(); maintenance = nil }
    }

    /// 退出本应用：所有画中画的窗口放回原处，正在回到原处的也算（同步，只在退出时用）。放到了才删恢复记录。
    func shutdown() {
        dropHint.cancel()
        maintenance?.invalidate()
        maintenance = nil
        let all = Array(sessions.values) + Array(exiting.values)
        sessions.removeAll()
        exiting.removeAll()
        order.removeAll()
        for s in all {
            s.animation?.invalidate()
            s.capture.stop()
            s.panel.orderOut(nil)
            s.tab?.orderOut(nil)
            if Self.place(s.element, at: homeFrame(s)) { clearRecord(s.id) }
        }
    }

    /// 显示器变了：画中画所在的那块屏不在了，或者原窗口推到哪边都会露在别的屏幕上，就回到原处；
    /// 其余的按现在的屏幕重新让开，面板摆回各自的角落。
    func screensChanged() {
        dropHint.cancel()
        for s in Array(sessions.values) {
            guard let screen = screenForDisplayID(s.displayID) else {
                wlog("pip: display gone id=\(s.id)")
                exit(s.id, activate: false)
                continue
            }
            guard s.parked else { continue }
            guard park(s, screen: screen) else {
                wlog("pip: nowhere to step aside id=\(s.id)")
                exit(s.id, activate: false)
                continue
            }
            if let side = s.stashed, let tab = s.tab {
                tab.setFrame(PiPLayout.tabFrame(side: side, midY: s.lastMidY, area: screen.visibleFrame, screen: screen.frame), display: true)
            }
        }
        for corner in PiPCorner.allCases { restack(corner: corner) }
    }

    /// 窗口关掉了、App 退出了、拿不到画面：画中画收掉，窗口还在的话放回原处。
    private func abandon(_ s: PiPSession, reason: String) {
        guard sessions[s.id] === s else { return }
        sessions[s.id] = nil
        order.removeAll { $0 == s.id }
        s.animation?.invalidate()
        s.capture.stop()
        s.panel.orderOut(nil)
        s.tab?.orderOut(nil)
        // 让开过、或者是从别处拖进角落的，放回原处；没挪过就只删恢复记录。
        if cgWindowInfo(s.id) != nil, s.parked || !s.original.equalTo(s.entered) {
            exiting[s.id] = s
            putBack(s, to: homeFrame(s), activate: false)
        } else {
            clearRecord(s.id)
        }
        restack(corner: s.corner)
        if sessions.isEmpty { maintenance?.invalidate(); maintenance = nil }
        wlog("pip: ended id=\(s.id) reason=\(reason)")
        if reason.hasPrefix("capture") || reason.hasPrefix("no shareable") {
            owner.notch.announce("这扇窗放不进画中画", detail: "拿不到它的画面", tone: .problem)
        }
    }

    private func ensureMaintenance() {
        guard maintenance == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for s in Array(self.sessions.values) {
                    guard let info = cgWindowInfo(s.id), (info[kCGWindowOwnerPID as String] as? pid_t) == s.pid else {
                        self.abandon(s, reason: "window gone")
                        continue
                    }
                }
            }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        maintenance = t
    }

    // MARK: - 让开

    /// 原窗口推到离它近的那条屏幕边外，只留两点：画面照样截得到，桌面上不挡东西。
    /// 两边都挨着别的屏幕（推过去会露在那块屏上）时不动，返回 false。已经停在该停的地方就不再写。
    private func park(_ s: PiPSession, screen: NSScreen) -> Bool {
        guard let parked = parkedFrame(CGRect(origin: s.original.origin, size: s.windowSize), on: screen) else { return false }
        if s.parked, s.parkedFrame?.equalTo(parked) == true { return true }
        s.parkedFrame = parked
        s.parked = true
        let element = s.element
        DispatchQueue.global(qos: .userInitiated).async { setAXPosition(element, parked.origin) }
        return true
    }

    private func parkedFrame(_ window: CGRect, on screen: NSScreen) -> CGRect? {
        let others = NSScreen.screens.filter { $0 != screen }.map { axRect($0.frame) }
        return PiPLayout.parked(window, screenAX: axRect(screen.frame), others: others)
    }

    // MARK: - 回到原处

    /// 回到原处的外框（AX 坐标）：进画中画之前的位置和大小；那块屏幕不在了就挪进还在的屏幕。
    private func homeFrame(_ s: PiPSession) -> CGRect {
        PiPLayout.restored(s.original, areas: NSScreen.screens.map { axRect($0.visibleFrame) })
    }

    /// 真窗口放回原处，在后台做，慢 App 不卡主线程；放到了才删恢复记录，放不到就留着，下次启动还能找回来。
    /// 放好之前这扇窗算在 exiting 里，不接新的画中画。
    private func putBack(_ s: PiPSession, to home: CGRect, activate: Bool) {
        let element = s.element, id = s.id, pid = s.pid
        DispatchQueue.global(qos: .userInitiated).async {
            let landed = Self.place(element, at: home)
            if activate { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    if activate { NSRunningApplication(processIdentifier: pid)?.activate() }
                    guard let self, self.exiting[id] === s else { return }
                    self.exiting[id] = nil
                    if landed { self.clearRecord(id) }
                }
            }
        }
    }

    /// 拖着标题栏进角落却放不进：窗口还停在松手的地方（在角落里，大半在屏幕外），挪回按住标题栏之前的地方。
    /// home 为 nil（快捷键、菜单进来）时窗口没被挪过，不动。
    private func putBackDropped(_ win: AXUIElement, home: CGRect?) {
        guard let home else { return }
        let target = PiPLayout.restored(home, areas: NSScreen.screens.map { axRect($0.visibleFrame) })
        DispatchQueue.global(qos: .userInitiated).async { _ = Self.place(win, at: target) }
    }

    /// 先挪回去；大小不对再改大小、再挪一次（有的 App 按窗口当时所在的屏幕夹大小）。读回来到位了返回 true。
    nonisolated private static func place(_ element: AXUIElement, at frame: CGRect) -> Bool {
        setAXPosition(element, frame.origin)
        if let size = axSize(element), abs(size.width - frame.width) > 1 || abs(size.height - frame.height) > 1 {
            setAXSize(element, frame.size)
            setAXPosition(element, frame.origin)
        }
        guard let observed = axPosition(element) else { return false }
        return hypot(observed.x - frame.minX, observed.y - frame.minY) < 8
    }

    /// 删这扇窗的恢复记录。侧拉接手了这扇窗时，那条记录已经换成侧拉的（同一个 id、同一份记录），不删。
    private func clearRecord(_ id: CGWindowID) {
        guard sessions[id] == nil, !owner.slideOver.isSlideOver(id) else { return }
        SlideOverRecovery.clear(id: id)
    }

    private func axRect(_ frame: NSRect) -> CGRect {
        CGRect(origin: axPosition(fromCocoaFrame: frame), size: frame.size)
    }

    // MARK: - 摆放

    private func screen(of s: PiPSession) -> NSScreen {
        screenForDisplayID(s.displayID) ?? NSScreen.screens.first { $0.frame.intersects(s.panel.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 这扇在它的角落里该在哪：同一角落里排在它前面的几扇先占着。
    /// 前面几扇按它们该有的大小算，不读面板现在的大小：换档、只看一块时面板还在动画里，读到的是旧尺寸。
    private func frame(for s: PiPSession, on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let before = order.prefix { $0 != s.id }.compactMap { sessions[$0] }
            .filter { $0.corner == s.corner && $0.stashed == nil && $0.displayID == s.displayID }
            .map { size(of: $0, area: area) }
        return PiPLayout.frame(corner: s.corner, size: size(of: s, area: area), area: area, stackedBefore: before)
    }

    private func size(of s: PiPSession, area: CGRect) -> CGSize {
        PiPLayout.size(source: s.crop?.size ?? s.windowSize, level: s.level, area: area)
    }

    private func pixels(_ size: CGSize, screen: NSScreen) -> CGSize {
        CGSize(width: size.width * screen.backingScaleFactor, height: size.height * screen.backingScaleFactor)
    }

    /// 一个角落里有一扇离开了：剩下的往角上靠。
    private func restack(corner: PiPCorner) {
        for id in order {
            guard let s = sessions[id], s.corner == corner, s.stashed == nil, !s.dragging else { continue }
            let target = frame(for: s, on: screen(of: s))
            if !target.equalTo(s.panel.frame) { animate(s.panel, to: target, velocity: .zero) }
        }
    }

    private func released(_ s: PiPSession, velocity: CGVector) {
        // 拖着的时候它已经在回到原处（松手晚到）：不再排进哪个角落。
        guard sessions[s.id] === s else { return }
        let screen = screen(of: s)
        switch PiPLayout.landing(frame: s.panel.frame, velocity: velocity, area: screen.visibleFrame, screen: screen.frame) {
        case .corner(let corner):
            let old = s.corner
            s.corner = corner
            // 换了角落才排到那一列最后；松回原来的角落就回自己那一格，不和摞在上面的那块叠在一起。
            if old != corner {
                order.removeAll { $0 == s.id }
                order.append(s.id)
            }
            animate(s.panel, to: frame(for: s, on: screen), velocity: velocity)
            if old != corner { restack(corner: old) }
            wlog("pip: id=\(s.id) to \(corner)")
        case .stash(let side):
            stash(s, side: side, velocity: velocity)
        }
    }

    /// 推到屏幕边外藏起来：边上留一小片带箭头的玻璃（和侧拉收起后的一样）；藏着时不截画面。
    private func stash(_ s: PiPSession, side: PiPSide, velocity: CGVector) {
        let screen = screen(of: s)
        s.stashed = side
        s.lastMidY = s.panel.frame.midY
        let target = PiPLayout.stashedFrame(s.panel.frame, side: side, screen: screen.frame)
        animate(s.panel, to: target, velocity: velocity) { [weak self] in
            guard let self, self.sessions[s.id] === s, s.stashed == side else { return }
            s.panel.orderOut(nil)
            s.capture.stop()
            let tab = s.tab ?? self.makeTab(for: s)
            s.tab = tab
            tab.setFrame(PiPLayout.tabFrame(side: side, midY: s.lastMidY, area: screen.visibleFrame, screen: screen.frame), display: true)
            (tab.contentView as? PiPTabView)?.side = side == .left ? .left : .right
            tab.alphaValue = 0
            tab.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; tab.animator().alphaValue = 1 }
            self.restack(corner: s.corner)
        }
        wlog("pip: id=\(s.id) stashed \(side)")
    }

    /// 从边上拉回来：重新开始截画面，回到原来那个角落。
    private func reveal(_ s: PiPSession, velocity: CGVector = .zero) {
        guard let side = s.stashed else { return }
        s.stashed = nil
        s.tab?.orderOut(nil)
        let screen = screen(of: s)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let content = try? await ShareableContentLoader.current()
            guard self.sessions[s.id] === s, let window = content?.windows.first(where: { $0.windowID == s.id }) else {
                self.abandon(s, reason: "window gone while stashed")
                return
            }
            let target = self.frame(for: s, on: screen)
            s.capture.setPictureInPictureOutput(pixels: self.pixels(target.size, screen: screen), source: s.crop)
            try? await s.capture.start(window: window, display: content?.displays.first { $0.displayID == s.displayID })
            // 开流的时候已经回到原处了：那边的停止可能早于开流，这里再停一次，不留一条没人看的流。
            guard self.sessions[s.id] === s else { s.capture.stop(); return }
            let from = PiPLayout.stashedFrame(target, side: side, screen: screen.frame)
            s.panel.setFrame(NSRect(x: from.minX, y: s.lastMidY - target.height / 2, width: target.width, height: target.height), display: false)
            s.panel.alphaValue = 1
            s.panel.orderFrontRegardless()
            self.animate(s.panel, to: target, velocity: velocity)
            self.restack(corner: s.corner)
        }
        wlog("pip: id=\(s.id) revealed from \(side)")
    }

    /// 三档大小之间换一档。
    private func step(_ s: PiPSession, bigger: Bool) {
        guard s.stashed == nil else { return }
        let next = PiPSizeLevel(rawValue: s.level.rawValue + (bigger ? 1 : -1))
        guard let next else { return }
        s.level = next
        let screen = screen(of: s)
        let target = frame(for: s, on: screen)
        s.capture.setPictureInPictureOutput(pixels: pixels(target.size, screen: screen), source: s.crop)
        animate(s.panel, to: target, velocity: .zero)
        restack(corner: s.corner)
    }

    // MARK: - 只看一块

    private func applyCrop(_ s: PiPSession, selection: CGRect?) {
        let showing = s.crop ?? CGRect(origin: .zero, size: s.windowSize)
        if let selection {
            guard let rect = PiPLayout.crop(selection: selection, viewSize: s.panel.frame.size, showing: showing) else { return }
            s.crop = rect
        } else {
            s.crop = nil
        }
        let screen = screen(of: s)
        let target = frame(for: s, on: screen)
        s.capture.setPictureInPictureOutput(pixels: pixels(target.size, screen: screen), source: s.crop)
        animate(s.panel, to: target, velocity: .zero)
        restack(corner: s.corner)
        wlog("pip: id=\(s.id) crop=\(s.crop.map { "\($0)" } ?? "whole window")")
    }

    // MARK: - 发给原窗口

    /// 画面里的一点对应到原窗口（它现在让开的位置）上的哪一点（AX 坐标）。
    private func windowPoint(_ s: PiPSession, viewPoint: CGPoint, viewSize: CGSize) -> CGPoint {
        let showing = s.crop ?? CGRect(origin: .zero, size: s.windowSize)
        let x = showing.minX + viewPoint.x / max(1, viewSize.width) * showing.width
        let y = showing.minY + (viewSize.height - viewPoint.y) / max(1, viewSize.height) * showing.height
        let origin = s.parkedFrame?.origin ?? s.entered.origin
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    /// 滚轮直接滚原窗口。定向发给那个 App 的滚动事件会被系统丢掉（2026-09-28 实测），
    /// 所以改用辅助功能：找到原窗口里对应那一点的滚动区，按像素换算成滚动条的位置写进去；窗口在屏幕外也有效。
    private func forwardScroll(_ s: PiPSession, event: NSEvent, viewPoint: CGPoint, viewSize: CGSize) {
        let lines = event.hasPreciseScrollingDeltas ? 1 : 16
        s.scroller.scroll(by: event.scrollingDeltaY * CGFloat(lines), at: windowPoint(s, viewPoint: viewPoint, viewSize: viewSize))
    }

    /// 上一页、下一页：画面正中那一点所在的滚动区滚一屏（看得见的高度的九成）。
    private func page(_ s: PiPSession, down: Bool) {
        let size = s.panel.frame.size
        s.scroller.page(down: down, at: windowPoint(s, viewPoint: CGPoint(x: size.width / 2, y: size.height / 2), viewSize: size))
        wlog("pip: id=\(s.id) page \(down ? "down" : "up")")
    }

    /// 播放 / 暂停：系统媒体键（交给正在播放的那个 App）。
    private func playPause() {
        let key: Int = 16 // NX_KEYTYPE_PLAY
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 面板

    private func wireUp(_ s: PiPSession) {
        let view = s.view
        view.onDragBegin = { [weak s] in s?.dragging = true; s?.capture.isInteractive = true }
        view.onDrag = { [weak s] delta in
            guard let s, let start = s.dragStart else { return }
            s.panel.setFrameOrigin(NSPoint(x: start.x + delta.dx, y: start.y + delta.dy))
        }
        view.onDragStart = { [weak s] in s?.dragStart = s?.panel.frame.origin; s?.animation?.invalidate() }
        view.onDragEnd = { [weak self, weak s] velocity in
            guard let self, let s else { return }
            s.dragging = false
            s.dragStart = nil
            self.released(s, velocity: velocity)
        }
        view.onDoubleClick = { [weak self, weak s] in if let s { self?.exit(s.id, activate: true) } }
        view.onClose = { [weak self, weak s] in if let s { self?.exit(s.id, activate: false) } }
        view.onReturn = { [weak self, weak s] in if let s { self?.exit(s.id, activate: true) } }
        view.onPage = { [weak self, weak s] down in if let s { self?.page(s, down: down) } }
        view.onPlayPause = { [weak self] in self?.playPause() }
        view.onResize = { [weak self, weak s] bigger in if let s { self?.step(s, bigger: bigger) } }
        view.onCrop = { [weak self, weak s] selection in if let s { self?.applyCrop(s, selection: selection) } }
        view.onScroll = { [weak self, weak s] event, point, size in
            if let s { self?.forwardScroll(s, event: event, viewPoint: point, viewSize: size) }
        }
        view.onHover = { [weak s] inside in s?.capture.isInteractive = inside || (s?.dragging ?? false) }
        view.hasCrop = { [weak s] in s?.crop != nil }
    }

    private func makeTab(for s: PiPSession) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: PiPLayout.tabSize), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        let view = PiPTabView(frame: NSRect(origin: .zero, size: PiPLayout.tabSize))
        view.onReveal = { [weak self, weak s] inward in if let s { self?.reveal(s, velocity: CGVector(dx: inward, dy: 0)) } }
        panel.contentView = view
        return panel
    }

    /// 面板走到 target：带着松手的速度（Cocoa 坐标，点/秒），临界阻尼的弹簧；和窗口滑行同一套路径。
    private func animate(_ panel: NSPanel, to target: NSRect, velocity: CGVector, duration: TimeInterval? = nil, done: (@MainActor () -> Void)? = nil) {
        let session = sessions.values.first { $0.panel === panel }
        session?.animation?.invalidate()
        let fromAX = CGRect(origin: axPosition(fromCocoaFrame: panel.frame), size: panel.frame.size)
        let toAX = CGRect(origin: axPosition(fromCocoaFrame: target), size: target.size)
        let path = FlickGlidePath.honoringMotion(from: fromAX, to: toAX, velocity: CGVector(dx: velocity.dx, dy: -velocity.dy))
        let length = Motion.reduced ? 0.12 : (duration ?? min(path.duration, 0.6))
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            let finished = MainActor.assumeIsolated { () -> Bool in
                let t = CACurrentMediaTime() - began
                let finished = t >= length
                let frameAX: CGRect
                if duration != nil || Motion.reduced {
                    let p = min(1, t / length)
                    let e = CGFloat(1 - pow(1 - p, 3))
                    frameAX = CGRect(x: fromAX.minX + (toAX.minX - fromAX.minX) * e, y: fromAX.minY + (toAX.minY - fromAX.minY) * e,
                                     width: fromAX.width + (toAX.width - fromAX.width) * e, height: fromAX.height + (toAX.height - fromAX.height) * e)
                } else {
                    frameAX = finished ? toAX : path.frame(at: t)
                }
                panel.setFrame(cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size), display: true)
                if finished {
                    panel.setFrame(target, display: true)
                    done?()
                }
                return finished
            }
            if finished { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        session?.animation = timer
    }
}

// MARK: - 一扇画中画

@MainActor
final class PiPSession {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    /// 进画中画之前窗口在哪（AX 坐标）：回到原处回这里。
    let original: CGRect
    /// 进画中画那一刻窗口实际在哪（AX 坐标）：从别处拖进角落时和 original 不同。
    let entered: CGRect
    let windowSize: CGSize
    let displayID: CGDirectDisplayID?
    var corner: PiPCorner
    var level: PiPSizeLevel = .small
    var crop: CGRect?
    var stashed: PiPSide?
    var lastMidY: CGFloat = 0
    var parked = false
    var parkedFrame: CGRect?
    var dragging = false
    var dragStart: NSPoint?
    var animation: Timer?
    let capture = WindowStreamCapture()
    /// 往原窗口的滚动区写滚动位置（后台串行，连续滚动只写最新的）。
    let scroller: PiPScroller
    let panel: NSPanel
    let view: PiPView
    var tab: NSPanel?

    init(id: CGWindowID, pid: pid_t, element: AXUIElement, original: CGRect, entered: CGRect, windowSize: CGSize, corner: PiPCorner,
         displayID: CGDirectDisplayID?) {
        self.id = id
        self.pid = pid
        self.element = element
        self.original = original
        self.entered = entered
        self.windowSize = windowSize
        self.corner = corner
        self.displayID = displayID
        scroller = PiPScroller(window: element)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 135), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // 画中画跟着你走：每张桌面都在，全屏 App 上也在。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.alphaValue = 0
        view = PiPView(frame: panel.contentLayoutRect, videoLayer: capture.videoLayer)
        panel.contentView = view
        // 不贴干净底片：底片按进画中画那一刻的整窗比例拍，“只看一块”之后比例变了会贴错位；
        // 红绿灯上的录屏胶囊照样抹平（只在左上角真的检测到胶囊时才动）。
        capture.takesCleanPlate = false
    }
}


// MARK: - 滚原窗口

/// 画中画里的滚轮、上一页、下一页落到原窗口：辅助功能找到那一点所在的滚动区（找不到就用最大的那一块），
/// 读它的文档高度和看得见的高度，把像素换算成竖向滚动条的位置写进去。在自己的串行队列上做，不卡主线程；
/// 滚得快时只累加，队列空下来一次写到位。找到的滚动区记 2 秒，连续滚动不用每次重找。
final class PiPScroller: @unchecked Sendable {
    private let window: AXUIElement
    private let queue = DispatchQueue(label: "WindowShade.pip-scroll", qos: .userInteractive)
    private let lock = NSLock()
    /// 还没写下去的滚动量（点）：正数是内容往下走（往上翻）。
    private var pending: CGFloat = 0
    private var pendingPages = 0
    private var point: CGPoint = .zero
    private var scheduled = false
    private var cached: (area: Area, at: CFTimeInterval)?
    private struct Area { let bar: AXUIElement; let visible: CGFloat; let document: CGFloat; let frame: CGRect }

    init(window: AXUIElement) { self.window = window }

    func scroll(by points: CGFloat, at point: CGPoint) {
        lock.lock(); pending += points; self.point = point; let start = !scheduled; scheduled = true; lock.unlock()
        if start { queue.async { self.drain() } }
    }

    func page(down: Bool, at point: CGPoint) {
        lock.lock(); pendingPages += down ? 1 : -1; self.point = point; let start = !scheduled; scheduled = true; lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            let points = pending, pages = pendingPages, at = point
            pending = 0; pendingPages = 0
            if points == 0 && pages == 0 { scheduled = false; lock.unlock(); return }
            lock.unlock()
            guard let area = area(near: at) else { continue }
            let range = max(1, area.document - area.visible)
            var value = number(area.bar, kAXValueAttribute) ?? 0
            value -= Double(points / range)
            value += Double(CGFloat(pages) * area.visible * 0.9 / range)
            AXUIElementSetAttributeValue(area.bar, kAXValueAttribute as CFString, NSNumber(value: min(1, max(0, value))))
        }
    }

    private func area(near point: CGPoint) -> Area? {
        if let cached, CACurrentMediaTime() - cached.at < 2, cached.area.frame.contains(point) { return cached.area }
        var found: [Area] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if role(element) == "AXScrollArea", let area = describe(element) { found.append(area) }
            guard depth < 7 else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                  let list = children as? [AXUIElement] else { continue }
            queue += list.map { ($0, depth + 1) }
        }
        let best = found.filter { $0.frame.contains(point) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? found.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        if let best { cached = (best, CACurrentMediaTime()) }
        return best
    }

    private func describe(_ area: AXUIElement) -> Area? {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(area, kAXVerticalScrollBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        let barElement = bar as! AXUIElement
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(barElement, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
              let frame = rect(area) else { return nil }
        var contents: CFTypeRef?
        AXUIElementCopyAttributeValue(area, kAXContentsAttribute as CFString, &contents)
        let document = (contents as? [AXUIElement] ?? []).compactMap { rect($0)?.height }.max() ?? frame.height
        guard document > frame.height + 1 else { return nil }
        return Area(bar: barElement, visible: frame.height, document: document, frame: frame)
    }

    private func role(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String
    }

    private func number(_ element: AXUIElement, _ attribute: String) -> Double? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? NSNumber)?.doubleValue
    }

    private func rect(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
}
