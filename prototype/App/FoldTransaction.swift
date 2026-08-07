// 折叠事务：真实窗口隐藏/恢复、焦点交接、折叠验证与回滚、
// 交通灯转发、AX 观察器与会话生命周期通知。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func parkFocusForInactiveCapture() {
        if focusParkingWindow == nil {
            let w = OverlayWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.alphaValue = 0
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.managed]
            focusParkingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        focusParkingWindow?.makeKeyAndOrderFront(nil)
    }

    func releaseFocusParking(reactivate pid: pid_t?) {
        focusParkingWindow?.orderOut(nil)
        if let pid = pid { activateApp(pid: pid) }
    }

    // MARK: 折叠事务：焦点交接
    //
    // 病灶：对焦点所在的 app/窗口执行 app-hide/minimize 时，macOS 自行挑选焦点
    // 继承人，其"下一个 app"逻辑遵循全局最近使用顺序、不限当前 Space——继承人在
    // 别的 Space 就跳 Space，继承人是同 app 其他窗口就"激活兄弟窗口"。而隐藏
    // 非前台 app/窗口没有任何焦点级联。所以隐藏之前由我们显式把焦点交给当前
    // Space 上的继承人：同 app 同 Space 其他窗口（菜单栏不变）→ 当前 Space
    // 最顶层其他 regular app 窗口（与系统自身最小化行为一致）→ Finder。
    // 返回值 = app-hide 是否安全（会不会触发系统的前台 app 重新选举）。
    // 隐藏整个 app 时，若它是前台 app，macOS 按全局最近使用顺序选举继任者，
    // 继任者的窗口在别的 Space 就会跳过去——这个选举我们无法干预。
    // 只有当焦点已交接到当前 Space 的其他窗口（或目标 app 本就不在前台）时，
    // app-hide 才不会触发选举。
    @discardableResult
    func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // 交接后撤掉截图期的焦点停靠（成功路径此前从不释放）。
        defer { focusParkingWindow?.orderOut(nil) }
        guard frontmostPid == pid || frontmostPid == selfPid else {
            return true   // 目标 app 本就不在前台，隐藏它不会触发焦点级联
        }

        let onScreenIDs = currentOnScreenWindowIDs()

        // 1) 同 app 在当前 Space 的另一个窗口：焦点交给它，app 保持前台，菜单栏不变。
        for candidate in appWindows(pid: pid) {
            guard !CFEqual(candidate, win),
                  !axBoolAttribute(candidate, kAXMinimizedAttribute as String),
                  let cid = windowID(of: candidate), cid != id,
                  onScreenIDs.contains(cid) else { continue }
            focusAXWindow(candidate, pid: pid)
            wlog("focus: handoff strategy=same-app heir=\(cid) id=\(id)")
            return true
        }

        // 2) 当前 Space 最顶层的其他 regular app 窗口。
        let windows = WindowListCache.shared.onScreenWindows()
        for info in windows {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  owner != pid, owner != selfPid,
                  ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  !overlayIDs.contains(CGWindowID(number.uint32Value)),
                  let bounds = cgWindowBounds(info), bounds.width > 1, bounds.height > 1,
                  let heirApp = NSRunningApplication(processIdentifier: owner),
                  heirApp.activationPolicy == .regular else { continue }
            heirApp.activate(options: [])
            var best: (win: AXUIElement, delta: CGFloat)?
            for heirWin in appWindows(pid: owner) {
                guard let p = axPosition(heirWin), let s = axSize(heirWin) else { continue }
                let delta = frameDistance(CGRect(origin: p, size: s), bounds)
                if delta <= 96, best == nil || delta < best!.delta {
                    best = (heirWin, delta)
                }
            }
            if let heirWin = best?.win {
                focusAXWindow(heirWin, pid: owner)
            }
            wlog("focus: handoff strategy=top-window heir=\(heirApp.localizedName ?? String(owner)) id=\(id)")
            return true
        }

        // 3) 当前 Space 没有任何其他窗口：无处交接。
        //    实测教训（13:37/13:49）：激活 Finder 会被 Mission Control 拉去它有
        //    窗口的 Space；焦点停靠 + app-hide 也躲不过系统的前台选举跳变；
        //    补偿式跳回受限于"新 Space 值在动画提交前读不到"，永远慢一拍。
        //    根治 = 不交接、返回 app-hide 不安全：调用方将禁用 app-hide 改走
        //    minimize——最小化不触发前台选举（app 保持前台，菜单栏不变），
        //    这是 macOS 的稳定语义（⌘M 从不切 Space）。
        wlog("focus: handoff strategy=stay-minimize id=\(id)")
        return false
    }

    // 折叠事务：隐藏生效验证。reveal overlay 之前必须确认真实窗口确实不可见，
    // 否则会出现 proxy 与真实窗口同框。
    func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,
                                id: CGWindowID, size: CGSize) -> Bool {
        switch hide {
        case .offscreen, .privateOffscreen:
            guard let p = axPosition(win) else { return true }   // 读不到几何按已隐藏处理
            return !windowIsVisible(pos: p, size: size)
        case .hidden:
            return runningApp(pid: pid)?.isHidden ?? true
        case .minimized:
            return axBoolAttribute(win, kAXMinimizedAttribute as String)
        case .privateAlpha:
            let alpha = PrivateSLSWindowMover.shared.windowAlpha(id: id) ?? 1
            return alpha <= 0.05
        case .none, .ownWindowOrderedOut, .quickLookClosed:
            return true
        }
    }

    // 延迟验证链：+0.15s / +0.45s 重查隐藏是否生效；通过 → reveal overlay；
    // 两次失败 → 补救 minimize（焦点已交接，无级联副作用）；补救仍失败 → 回滚。
    // overlay 在验证通过前保持隐形，保证 proxy 与真实窗口永不同框。
    func scheduleFoldVerification(id: CGWindowID, attempt: Int) {
        let delay = attempt == 1 ? 0.15 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let state = self.shaded[id],
                  state.lifecycleStage == .folded else { return }
            if self.hideTookEffect(state.hide, win: state.element, pid: state.pid,
                                   id: id, size: state.originalSize) {
                wlog("shade: hide verified attempt=\(attempt) id=\(id) hide=\(state.hide)")
                self.revealOverlayAfterVerification(id: id, state: state)
                return
            }
            if attempt == 1 {
                self.scheduleFoldVerification(id: id, attempt: 2)
                return
            }
            setAXMinimized(state.element, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, var latest = self.shaded[id],
                      latest.lifecycleStage == .folded else { return }
                if self.hideTookEffect(.minimized, win: latest.element, pid: latest.pid,
                                       id: id, size: latest.originalSize) {
                    latest.hide = .minimized
                    self.shaded[id] = latest
                    wlog("shade: hide salvaged via minimize id=\(id) app=\(latest.appName)")
                    self.revealOverlayAfterVerification(id: id, state: latest)
                    return
                }
                wlog("shade: hide failed after salvage; rolling back id=\(id) app=\(latest.appName)")
                self.rollbackFoldTransaction(id: id)
            }
        }
    }

    func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {
        guard let overlay = state.overlay else { return }
        if enforceOverlaySpaceInvariant(id: id, state: state, reason: "hide-verified") {
            revealPreparedOverlay(overlay)
        }
    }

    // 回滚折叠事务：按已尝试的隐藏方式逐项逆操作（此前的回滚漏了这步，
    // 曾把实际已 app-hide 的 Safari 留在隐藏态、无卷帘条），再恢复几何、
    // 撤 overlay/状态/journal。
    func rollbackFoldTransaction(id: CGWindowID) {
        guard let state = shaded[id] else { return }
        switch state.hide {
        case .hidden:
            if NSRunningApplication(processIdentifier: state.pid)?.unhide() != true {
                _ = setAXAppHidden(pid: state.pid, false)
            }
        case .minimized:
            setAXMinimized(resolvedWindowElement(for: state), false)
        case .privateAlpha:
            let alpha = privateAlphaOriginalValues.removeValue(forKey: id) ?? 1
            _ = PrivateSLSWindowMover.shared.setAlpha(id: id, alpha: alpha)
        case .none, .offscreen, .privateOffscreen, .ownWindowOrderedOut, .quickLookClosed:
            break
        }
        _ = applyRestoredGeometry(state, to: state.originalPosition, label: "rollback", reason: "restore")
        forceCleanup(id)
        quietNotice("此窗口暂时无法折叠",
                    log: "shade: transaction rolled back id=\(id) app=\(state.appName)")
    }

    func activateApp(pid: pid_t) {
        guard let app = runningApp(pid: pid) else { return }
        app.unhide()
        app.activate(options: [])
    }

    func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {
        func attempt(_ label: String) {
            // 只在 app 尚未前台时 activate：250ms 内连发 activate 会反复重启
            // 菜单栏的交叉淡入，赶上时机就把两套菜单叠印留在屏幕上（系统级
            // 渲染残影，实测截图 2026-07）。激活已生效的重试只做 AX raise/focus
            // （不触碰菜单栏）；unhide 保留（.hidden 恢复路径依赖，且幂等）。
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                activateApp(pid: pid)
            } else {
                runningApp(pid: pid)?.unhide()
            }
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            wlog("front: \(reason) \(label)")
        }

        attempt("immediate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attempt("after-80ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt("after-250ms") }
    }

    func prepareForwardedTrafficAction(_ win: AXUIElement, pid: pid_t, reason: String) {
        activateApp(pid: pid)
        raiseAXWindow(win)
        focusAXWindow(win, pid: pid)
        wlog("front: \(reason) immediate-only")
    }

    func restoredWindowIsGeometryReady(_ win: AXUIElement) -> Bool {
        guard let pos = axPosition(win), let size = axSize(win) else { return false }
        return pos.x.isFinite && pos.y.isFinite && size.width > 1 && size.height > 1
    }

    func buttonIsReady(_ win: AXUIElement, _ attr: String) -> Bool {
        guard let button = axButtonElement(win, attr),
              let pos = axPosition(button),
              let size = axSize(button),
              size.width > 1,
              size.height > 1,
              pos.x.isFinite,
              pos.y.isFinite else { return false }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &ref) == .success,
           let value = ref {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return CFBooleanGetValue((value as! CFBoolean))
            }
            return (value as? NSNumber)?.boolValue ?? true
        }
        return true
    }

    func forwardedTrafficActionSucceeded(state: ShadeState, id: CGWindowID,
                                                 win: AXUIElement,
                                                 action: TrafficAction) -> Bool {
        switch action {
        case .minimize:
            return axBoolAttribute(win, kAXMinimizedAttribute as String)
        case .close:
            guard runningApp(pid: state.pid) != nil else { return true }
            let windows = appWindows(pid: state.pid)
            guard !windows.isEmpty else { return true }
            let sameWindowExists = windows.contains { window in
                if let currentID = windowID(of: window), currentID == id { return true }
                let expectedTitle = cleanDisplayTitle(state.title)
                return !expectedTitle.isEmpty && cleanDisplayTitle(axTitle(window)) == expectedTitle
            }
            guard sameWindowExists else { return true }
            guard let pos = axPosition(win), let size = axSize(win) else { return true }
            return !windowIsVisible(pos: pos, size: size)
        case .zoom, .fullScreen:
            return true
        }
    }

    func performForwardedTrafficAction(state: ShadeState, pos: CGPoint,
                                               id: CGWindowID, action: TrafficAction) {
        let attrs: [String]
        switch action {
        case .close:
            attrs = [kAXCloseButtonAttribute as String]
        case .minimize:
            attrs = [kAXMinimizeButtonAttribute as String]
        case .zoom:
            attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
        case .fullScreen:
            attrs = [kAXFullScreenButtonAttribute as String]
        }

        func retryOrFallback(_ index: Int, note: String) {
            if action == .minimize, index >= forwardedTrafficRetryDelays.count - 1 {
                let win = resolvedWindowElement(for: state)
                setAXMinimized(win, true)
                wlog("traffic: minimize fallback AXMinimized id=\(id) note=\(note)")
                return
            }
            if action == .zoom, index >= forwardedTrafficRetryDelays.count - 1 {
                pressFullScreenShortcut()
                wlog("traffic: zoom fallback ctrl-cmd-f id=\(id) note=\(note)")
                return
            }
            if action == .fullScreen, index >= forwardedTrafficRetryDelays.count - 1 {
                pressFullScreenShortcut()
                wlog("traffic: fullscreen fallback ctrl-cmd-f id=\(id) note=\(note)")
                return
            }
            if action == .close, index >= forwardedTrafficRetryDelays.count - 1 {
                wlog("traffic: close failed id=\(id) note=\(note)")
                return
            }
            schedule(index + 1, note: note)
        }

        func verifyAfterAXPress(_ win: AXUIElement, index: Int, attr: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                let latest = self.resolvedWindowElement(for: state)
                if self.forwardedTrafficActionSucceeded(state: state, id: id,
                                                        win: latest, action: action) {
                    wlog("traffic: \(action) AXPress verified id=\(id) attr=\(attr) attempt=\(index)")
                    return
                }
                retryOrFallback(index, note: "axpress-no-effect")
            }
        }

        func verifyAfterPointerClick(_ win: AXUIElement, index: Int, attr: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                let latest = self.resolvedWindowElement(for: state)
                if self.forwardedTrafficActionSucceeded(state: state, id: id,
                                                        win: latest, action: action) {
                    wlog("traffic: \(action) pointer-click verified id=\(id) attr=\(attr) attempt=\(index)")
                    return
                }
                if pressAXButton(latest, attr) {
                    wlog("traffic: \(action) AXPress fallback id=\(id) attr=\(attr) attempt=\(index)")
                    verifyAfterAXPress(latest, index: index, attr: attr)
                    return
                }
                retryOrFallback(index, note: "click-no-effect")
            }
        }

        func attempt(_ index: Int) {
            let win = applyRestoredGeometry(state, to: pos,
                                            label: "traffic-\(index)",
                                            reason: "traffic \(action) id=\(id)")
            prepareForwardedTrafficAction(win, pid: state.pid,
                                          reason: "traffic-\(action) id=\(id) attempt=\(index)")
            guard restoredWindowIsGeometryReady(win) else {
                schedule(index + 1, note: "geometry-not-ready")
                return
            }

            if let attr = attrs.first(where: { buttonIsReady(win, $0) }) {
                // Forward as a real pointer click at the real traffic-light
                // center. Nonstandard apps such as WeChat may ignore AXPress
                // here, but they still honor the native mouse path.
                if clickAXButton(win, attr) {
                    wlog("traffic: \(action) pointer-click forwarded id=\(id) attr=\(attr) attempt=\(index)")
                    if action == .zoom || action == .fullScreen { return }
                    verifyAfterPointerClick(win, index: index, attr: attr)
                    return
                }
                if pressAXButton(win, attr) {
                    wlog("traffic: \(action) AXPress forwarded id=\(id) attr=\(attr) attempt=\(index)")
                    verifyAfterAXPress(win, index: index, attr: attr)
                    return
                }
            }

            retryOrFallback(index, note: "button-not-ready")
        }

        func schedule(_ index: Int, note: String) {
            guard index < forwardedTrafficRetryDelays.count else {
                wlog("traffic: \(action) failed id=\(id) note=\(note)")
                return
            }
            let delay = forwardedTrafficRetryDelays[index]
            wlog("traffic: \(action) retry id=\(id) attempt=\(index) delay=\(String(format: "%.2f", delay)) note=\(note)")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(index)
            }
        }

        attempt(0)
    }

    func triggerFullScreenOnRestoredWindow(_ win: AXUIElement, pid: pid_t) {
        bringRestoredWindowToFront(win, pid: pid, reason: "fullscreen")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.bringRestoredWindowToFront(win, pid: pid, reason: "fullscreen-before-click")
            if clickAXButton(win, kAXFullScreenButtonAttribute as String) {
                wlog("fullscreen: clicked real fullscreen button")
                return
            }
            if pressAXButton(win, kAXFullScreenButtonAttribute as String) {
                wlog("fullscreen: AX fullscreen press")
                return
            }
            pressFullScreenShortcut()
            wlog("fullscreen: sent ctrl-cmd-f fallback")
        }
    }

    func showRealWindowManagementPopover(_ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        guard state.hide != .quickLookClosed else {
            wlog("proxy wm: skip QuickLook proxy id=\(id)")
            return
        }
        let pos = axPosition(fromCocoaFrame: restoreReferenceFrame(id: id, overlay: overlay))
        removeProxyForForwardedAction(id, state: state)
        let immediate = restoreWindow(state, to: pos)
        prepareForwardedTrafficAction(immediate, pid: state.pid,
                                      reason: "wm-popover id=\(id) immediate")

        let delays: [TimeInterval] = [0.05, 0.12, 0.22, 0.38, 0.60]
        func attempt(_ index: Int) {
            let win = applyRestoredGeometry(state, to: pos,
                                            label: "wm-\(index)",
                                            reason: "wm-popover id=\(id)")
            prepareForwardedTrafficAction(win, pid: state.pid,
                                          reason: "wm-popover id=\(id) attempt=\(index)")
            let attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
            if let attr = attrs.first(where: { buttonIsReady(win, $0) }),
               hoverAXButtonForWindowManagement(win, attr) {
                wlog("proxy wm: forwarded hover to real green button id=\(id) attr=\(attr) attempt=\(index)")
                return
            }
            if index + 1 < delays.count {
                wlog("proxy wm: retry hover id=\(id) attempt=\(index + 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[index + 1]) {
                    attempt(index + 1)
                }
            } else {
                wlog("proxy wm: cannot find real green button id=\(id)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[0]) {
            attempt(0)
        }
    }


    // MARK: 展开

    func windowIsParkedOffscreen(id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {
        if let cgVisible = cgWindowIsVisible(id: id, fallbackSize: size) {
            return !cgVisible
        }
        guard let pos = axPosition(win) else { return false }
        return !windowIsVisible(pos: pos, size: size)
    }

    func privateSLSOffscreenHide(_ win: AXUIElement, id: CGWindowID,
                                         originalPosition pos: CGPoint,
                                         size: CGSize,
                                         pid: pid_t,
                                         reason: String) -> HideMethod? {
        let mover = PrivateSLSWindowMover.shared
        guard mover.isAvailable else {
            wlog("    private SLS offscreen unavailable（pid=\(pid), reason=\(reason)）")
            return nil
        }

        let spots = [
            offscreen,
            CGPoint(x: -12000, y: pos.y),
            CGPoint(x: pos.x, y: -12000),
            CGPoint(x: -12000, y: -12000)
        ]
        for spot in spots {
            guard mover.moveWindow(id: id, to: spot) else {
                wlog("    private SLS move failed id=\(id) target=(\(Int(spot.x)),\(Int(spot.y))) reason=\(reason)")
                continue
            }

            if windowIsParkedOffscreen(id: id, win: win, size: size) {
                wlog("    private SLS offscreen → parked id=\(id) pid=\(pid) target=(\(Int(spot.x)),\(Int(spot.y))) reason=\(reason)")
                return .privateOffscreen
            }
        }

        if !windowIsParkedOffscreen(id: id, win: win, size: size) {
            _ = mover.moveWindow(id: id, to: pos)
        }
        wlog("    private SLS offscreen did not park id=\(id) pid=\(pid) reason=\(reason)")
        return nil
    }

    func privateSLSAlphaHide(id: CGWindowID, pid: pid_t, reason: String) -> HideMethod? {
        let mover = PrivateSLSWindowMover.shared
        guard mover.canSetAlpha else {
            wlog("    private SLS alpha unavailable（pid=\(pid), reason=\(reason)）")
            return nil
        }

        let originalAlpha = mover.windowAlpha(id: id) ?? Float((cgWindowInfo(id)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        guard mover.setAlpha(id: id, alpha: 0) else {
            wlog("    private SLS alpha failed id=\(id) pid=\(pid) reason=\(reason)")
            return nil
        }

        let currentAlpha = mover.windowAlpha(id: id)
            ?? Float((cgWindowInfo(id)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        guard currentAlpha <= 0.05 else {
            _ = mover.setAlpha(id: id, alpha: originalAlpha)
            wlog("    private SLS alpha did not apply id=\(id) pid=\(pid) current=\(String(format: "%.2f", currentAlpha)) reason=\(reason)")
            return nil
        }

        privateAlphaOriginalValues[id] = max(0.05, min(originalAlpha, 1.0))
        wlog("    private SLS alpha → hidden id=\(id) pid=\(pid) original=\(String(format: "%.2f", originalAlpha)) reason=\(reason)")
        return .privateAlpha
    }

    func axOffscreenHide(_ win: AXUIElement,
                                 originalPosition pos: CGPoint,
                                 size: CGSize,
                                 pid: pid_t,
                                 reason: String) -> HideMethod? {
        let spots = [
            offscreen,
            CGPoint(x: -12000, y: pos.y),
            CGPoint(x: pos.x, y: -12000),
            CGPoint(x: -12000, y: -12000)
        ]
        for spot in spots {
            setAXPosition(win, spot)
            guard let p2 = axPosition(win) else { continue }
            if !windowIsVisible(pos: p2, size: size) {
                wlog("    AX offscreen → parked（pid=\(pid), pos=(\(Int(p2.x)),\(Int(p2.y))), reason=\(reason)）")
                return .offscreen
            }
            wlog("    AX offscreen clamped（pid=\(pid), target=(\(Int(spot.x)),\(Int(spot.y))), actual=(\(Int(p2.x)),\(Int(p2.y))), reason=\(reason)）")
        }
        setAXPosition(win, pos)
        return nil
    }

    func ownWindow(id: CGWindowID?) -> NSWindow? {
        guard let id else { return nil }
        return NSApp.windows.first { window in
            cgWindowID(for: window) == id
        }
    }

    func orderOutOwnWindowIfNeeded(id: CGWindowID?, pid: pid_t, reason: String) -> HideMethod? {
        guard pid == getpid(), let window = ownWindow(id: id) else { return nil }
        window.orderOut(nil)
        guard !window.isVisible else {
            wlog("    own window orderOut failed id=\(id ?? 0) reason=\(reason)")
            return nil
        }
        wlog("    own window → orderedOut id=\(id ?? 0) reason=\(reason)")
        return .ownWindowOrderedOut
    }

    func hideWindow(_ win: AXUIElement, pid: pid_t, originalPosition pos: CGPoint,
                            size: CGSize, policy: ShadePolicy,
                            appHideSafe: Bool = true) -> HideMethod {
        let id = windowID(of: win)
        if let hide = orderOutOwnWindowIfNeeded(id: id, pid: pid, reason: "shade") {
            return hide
        }
        switch policy {
        case .closeQuickLookPreview:
            if pressAXButton(win, kAXCloseButtonAttribute as String) {
                wlog("    quicklook → closed via AX close（pid=\(pid)）")
                return .quickLookClosed
            }
            wlog("    quicklook close rejected; fallback offscreen（pid=\(pid)）")
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: false)
        case .hiddenIfSingleWindowElseMinimized(let allowAppHide):
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: allowAppHide && appHideSafe)
        case .offscreenForLivePreview:
            let livePreviewParkingSpots = [
                offscreen,
                CGPoint(x: -12000, y: pos.y),
                CGPoint(x: pos.x, y: -12000),
                CGPoint(x: -12000, y: -12000)
            ]
            for spot in livePreviewParkingSpots {
                setAXPosition(win, spot)
                if let p2 = axPosition(win), !windowIsVisible(pos: p2, size: size) {
                    wlog("    live preview parking → offscreen（pid=\(pid), pos=(\(Int(p2.x)),\(Int(p2.y))))")
                    return .offscreen
                }
            }
            setAXPosition(win, pos)
            wlog("    live preview parking failed; fallback to app-hide when single-window（pid=\(pid)）")
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: appHideSafe)
        case .offscreenThenFallback(let allowAppHide):
            let bundleID = appBundleID(pid: pid)
            if allowAppHide && appHideSafe && appCurrentUserWindowCount(pid) <= 1 {
                wlog("    single-window app → prefer hide fallback（pid=\(pid), bundle=\(bundleID)）")
                return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                    size: size, allowAppHide: true)
            }
            if let hide = axOffscreenHide(win, originalPosition: pos, size: size,
                                          pid: pid, reason: "shade") {
                return hide
            } else {
                clampingApps.insert(pid)              // 被钳制回可见区 → 记下来，但下次仍先重试当前窗口
                if !bundleID.isEmpty {
                    clampingBundleIDs.insert(bundleID)
                    UserDefaults.standard.set(Array(clampingBundleIDs).sorted(), forKey: clampingBundleIDsDefaultsKey)
                }
                let hide = fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                        size: size, allowAppHide: allowAppHide && appHideSafe)
                wlog("    挪屏外被钳制 → \(hide)（pid=\(pid), bundle=\(bundleID), allowAppHide=\(allowAppHide && appHideSafe)）")
                return hide
            }
        }
    }

    // 挪不出屏的 app：可安全整体隐藏时用 ⌘H 式隐藏；否则只最小化当前窗口。
    // 注意：app hide 只是现代 macOS 限制下的实现 fallback。产品语义仍然是
    // “折叠这个窗口”，所以只有当前 app 没有其它可见用户窗口时才允许整体隐藏。
    func fallbackHide(_ win: AXUIElement, pid: pid_t, id: CGWindowID?,
                              originalPosition pos: CGPoint, size: CGSize,
                              allowAppHide: Bool) -> HideMethod {
        let currentWindowCount = appCurrentUserWindowCount(pid)
        let totalWindowCount = appWindowCount(pid)
        if allowAppHide && currentWindowCount <= 1 {
            if setAXAppHidden(pid: pid, true) {
                wlog("    fallback → hidden via AX（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
                return .hidden
            }
            if NSRunningApplication(processIdentifier: pid)?.hide() == true {
                wlog("    fallback → hidden via NSRunningApplication（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
                return .hidden
            }
            wlog("    fallback hidden rejected（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
        }
        if let id,
           let hide = privateSLSOffscreenHide(win, id: id, originalPosition: pos,
                                              size: size, pid: pid, reason: "fallback") {
            return hide
        }
        if let id,
           let hide = privateSLSAlphaHide(id: id, pid: pid, reason: "fallback") {
            return hide
        }
        setAXMinimized(win, true)
        wlog("    fallback → minimized（pid=\(pid), allowAppHide=\(allowAppHide), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
        return .minimized
    }

    func safeRestorePosition(for state: ShadeState, desired pos: CGPoint) -> CGPoint {
        guard !windowIsVisible(pos: pos, size: state.originalSize) else { return pos }
        let frame = cocoaFrame(fromAXPosition: pos, size: state.originalSize)
        let clamped = clampedFrame(frame, margin: 16, preferredDisplayID: state.sourceDisplayID)
        return axPosition(fromCocoaFrame: clamped)
    }

    func resolvedWindowElement(for state: ShadeState) -> AXUIElement {
        let windows = appWindows(pid: state.pid)
        guard !windows.isEmpty else { return state.element }

        if let match = windows.first(where: { windowID(of: $0) == state.sourceWindowID }) {
            return match
        }
        if windows.count == 1 {
            return windows[0]
        }
        let stateTitle = cleanDisplayTitle(state.title)
        let titleMatches = !stateTitle.isEmpty
            ? windows.filter { cleanDisplayTitle(axTitle($0)) == stateTitle }
            : []
        if titleMatches.count == 1, let match = titleMatches.first {
            return match
        }
        if let pos = axPosition(state.element), let size = axSize(state.element) {
            let oldFrame = CGRect(origin: pos, size: size)
            let candidates = titleMatches.isEmpty ? windows : titleMatches
            return candidates.min {
                let aFrame = CGRect(origin: axPosition($0) ?? pos, size: axSize($0) ?? size)
                let bFrame = CGRect(origin: axPosition($1) ?? pos, size: axSize($1) ?? size)
                return frameDistance(aFrame, oldFrame) < frameDistance(bFrame, oldFrame)
            } ?? state.element
        }
        return state.element
    }

    func applyRestoredGeometry(_ state: ShadeState, to pos: CGPoint,
                                       label: String, reason: String) -> AXUIElement {
        let win = resolvedWindowElement(for: state)
        let safePos = safeRestorePosition(for: state, desired: pos)
        let sizeErr = setAXSize(win, state.originalSize)
        let posErr = setAXPositionReturningError(win, safePos)
        let actualPos = axPosition(win)
        let actualSize = axSize(win)
        let actual = actualPos.flatMap { p in
            actualSize.map { s in " actual=(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" }
        } ?? " actual=<unavailable>"
        wlog("geometry: \(reason) \(label) target=(\(Int(safePos.x)),\(Int(safePos.y)) \(Int(state.originalSize.width))x\(Int(state.originalSize.height))) err=(size:\(sizeErr),pos:\(posErr))\(actual)")
        if safePos != pos {
            wlog("restore: clamped invisible target app=\(state.appName) pos=(\(Int(safePos.x)),\(Int(safePos.y)))")
        }
        return win
    }

    // 按隐藏方式把真窗口恢复可见，并放到指定位置
    @discardableResult
    func restoreWindow(_ state: ShadeState, to pos: CGPoint) -> AXUIElement {
        switch state.hide {
        case .none:      break
        case .offscreen: break
        case .privateOffscreen:
            if PrivateSLSWindowMover.shared.moveWindow(id: state.sourceWindowID, to: pos) {
                wlog("restore: private SLS move back id=\(state.sourceWindowID) target=(\(Int(pos.x)),\(Int(pos.y)))")
            } else {
                wlog("restore: private SLS move back unavailable id=\(state.sourceWindowID)")
            }
        case .privateAlpha:
            let alpha = privateAlphaOriginalValues.removeValue(forKey: state.sourceWindowID) ?? 1
            if PrivateSLSWindowMover.shared.setAlpha(id: state.sourceWindowID, alpha: alpha) {
                wlog("restore: private SLS alpha back id=\(state.sourceWindowID) alpha=\(String(format: "%.2f", alpha))")
            } else {
                wlog("restore: private SLS alpha restore unavailable id=\(state.sourceWindowID)")
            }
        case .hidden:
            if NSRunningApplication(processIdentifier: state.pid)?.unhide() != true {
                _ = setAXAppHidden(pid: state.pid, false)
            }
        case .minimized:
            // hide/minimize 周期后原 AX 元素可能失效（Safari 常见），先重新解析，
            // 否则解除的是无效元素或错误窗口，表现为"恢复失败/几何漂移"。
            setAXMinimized(resolvedWindowElement(for: state), false)
        case .ownWindowOrderedOut:
            if let window = ownWindow(id: state.sourceWindowID) {
                let safePos = safeRestorePosition(for: state, desired: pos)
                window.setFrame(cocoaFrame(fromAXPosition: safePos, size: state.originalSize), display: true)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                wlog("restore: own window ordered front id=\(state.sourceWindowID) target=(\(Int(safePos.x)),\(Int(safePos.y)))")
            } else {
                wlog("restore: own window unavailable id=\(state.sourceWindowID)")
            }
        case .quickLookClosed: break
        }
        return applyRestoredGeometry(state, to: pos, label: "immediate", reason: "restore")
    }

    func cancelRestorePin(for id: CGWindowID) {
        restorePinTokens[id] = UUID()
    }

    func pinRestoredWindow(_ state: ShadeState, to pos: CGPoint, reason: String) {
        let id = state.sourceWindowID
        let token = UUID()
        restorePinTokens[id] = token

        // 前几次尝试只校正几何，最后一次才 raise+focus：旧实现每次尝试都重新
        // 激活/聚焦，restoreAll 批量展开时会造成焦点连环跳（每次 3~4 次 focus）。
        func attempt(_ label: String, focus: Bool) {
            guard restorePinTokens[id] == token else { return }
            let win = applyRestoredGeometry(state, to: pos, label: label, reason: reason)
            if focus {
                raiseAXWindow(win)
                focusAXWindow(win, pid: state.pid)
            }
        }

        // Safari 等 app 从 unhide/unminimize 自恢复窗口帧可晚于 550ms（"大窗口
        // 恢复成小窗口"的窗口期），只对这两种 hide 方式追加一次晚校验。
        let needsLatePin = state.hide == .hidden || state.hide == .minimized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attempt("after-80ms", focus: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt("after-250ms", focus: false) }
        if needsLatePin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { attempt("after-550ms", focus: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) { attempt("after-1100ms", focus: true) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { attempt("after-550ms", focus: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsLatePin ? 1.25 : 0.70)) { [weak self] in
            if self?.restorePinTokens[id] == token {
                self?.restorePinTokens.removeValue(forKey: id)
            }
        }
    }

    func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {
        guard var state = shaded[id], state.appearanceMode == .proxyTitleBar else { return }
        guard (state.overlay as? NativeProxyOverlayWindow)?.allowsHorizontalResize != false else { return }
        if let overlay = state.overlay as? NativeProxyOverlayWindow,
           abs(proxyFrame.height - overlay.fixedTitlebarHeight) > 0.5 {
            var corrected = proxyFrame
            corrected.origin.y += proxyFrame.height - overlay.fixedTitlebarHeight
            corrected.size.height = overlay.fixedTitlebarHeight
            overlay.setFrame(corrected, display: true)
        }
        let oldSize = state.originalSize
        guard oldSize.width > 1, oldSize.height > 1 else { return }
        let minWidth = (state.overlay as? NativeProxyOverlayWindow)?.minimumReadableWidth ?? 260
        let newWidth = max(minWidth, proxyFrame.width)
        let aspect = oldSize.height / oldSize.width
        let newHeight = max(proxyTitleBarHeight, newWidth * aspect)
        let newSize = CGSize(width: newWidth, height: newHeight)
        if abs(newSize.width - oldSize.width) < 0.5 && abs(newSize.height - oldSize.height) < 0.5 {
            return
        }
        state.originalSize = newSize
        shaded[id] = state
        if focusPulledOutOverlayIDs.contains(id) {
            if shouldReturnPulledOutOverlayToStack(id: id, frame: proxyFrame) {
                _ = restorePulledOutOverlayToStack(id: id)
                return
            }
            focusPulledOutRestoreFrames[id] = focusRestoreFrame(fromOverlayFrame: proxyFrame,
                                                                 restoredSize: newSize)
        }
        if !focusPulledOutOverlayIDs.contains(id) {
            arrangedOverlayFrames.removeValue(forKey: id)
        }
        syncRestoreJournal(id: id, fromOverlayFrame: state.overlay?.frame ?? proxyFrame, restoredSize: newSize)
        wlog("resize: proxy id=\(id) width=\(Int(newWidth)) restoredSize=(\(Int(newSize.width))x\(Int(newSize.height)))")
    }

    // 监听窗口被外部唤回：app 显示(⌘Tab 取消隐藏) / 取消最小化(点 Dock)。
    // app activated 只说明应用拿到焦点，不代表真实窗口已经回到用户可见位置；不能据此展开。
    func makeRevealObserver(pid: pid_t, win: AXUIElement, id: CGWindowID) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axWindowCallback, &observer) == .success, let obs = observer else { return nil }
        let app = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(id))
        AXObserverAddNotification(obs, app, kAXApplicationShownNotification as CFString, refcon)
        AXObserverAddNotification(obs, win, kAXWindowDeminiaturizedNotification as CFString, refcon)
        AXObserverAddNotification(obs, win, kAXUIElementDestroyedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        return obs
    }

    func removeObserver(_ state: ShadeState) {
        if let obs = state.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }

    func handleAXNotification(_ id: CGWindowID, _ notification: String) {
        guard let state = shaded[id] else { return }
        if notification == (kAXUIElementDestroyedNotification as String) {
            if state.hide == .quickLookClosed {
                wlog("quicklook: ignore expected destroyed notification id=\(id)")
                return
            }
            forceCleanup(id)
            return
        }
        if notification == (kAXWindowDeminiaturizedNotification as String) {
            if state.hide == .minimized {
                if isFocusShelfMember(id: id) {
                    revealFocusShelfMemberFromOutside(id: id, state: state, reason: "deminiaturized")
                    return
                }
                unshade(id)
            }
        } else if notification == (kAXApplicationShownNotification as String) {
            if Date() < state.ignoreAppRevealUntil {
                wlog("ignore early app reveal notification=\(notification) id=\(id) app=\(state.appName)")
                return
            }
            if state.hide == .hidden {
                if isFocusShelfMember(id: id) {
                    revealFocusShelfMemberFromOutside(id: id, state: state, reason: "app-shown")
                    return
                }
                unshade(id)
            }
        } else {
            wlog("ignore reveal notification=\(notification) id=\(id) app=\(state.appName)")
        }
    }

    @objc func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        pinnedPreviewController.stopPreviews(forPID: app.processIdentifier, reason: "source-app-terminated")
        for id in shaded.filter({ $0.value.pid == app.processIdentifier }).map(\.key) {
            forceCleanup(id)
        }
    }

    @objc func frontmostApplicationChanged(_ note: Notification) {
        hideHoverPreview()
        hideMenuHoverPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refreshPinnedPreviewTarget(reason: "frontmost-app")
        }
        refreshOverlayPresentation()
    }









    @objc func screenParametersChanged(_ note: Notification) {
        pinnedPreviewController.refreshAll(reason: "screen")
        for (id, state) in shaded {
            guard let overlay = state.overlay else { continue }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                if arrangedOverlayFrames[id] == nil {
                    syncRestoreJournal(id: id, fromOverlayFrame: newFrame)
                }
                wlog("screen: clamped overlay id=\(id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
        }
        if shaded.isEmpty {
            rescueOffscreenWindows(silent: true)
        }
    }

    @objc func activeSpaceChanged(_ note: Notification) {
        restorePendingSourceSpacesIfNeeded(reason: "active-space-changed")
        // 轻操作即时执行；开启置顶预览的动画抑制窗口期。
        hideHoverPreview()
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
        pinnedPreviewController.noteSpaceTransition()
        // 重操作（逐窗口 AX/WindowServer 查询 + overlay space enforce）合并防抖：
        // 连续切 Space / 切换动画期间的通知风暴只结算一次。
        spaceRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spaceRefreshWorkItem = nil
            self.pinnedPreviewController.refreshAll(reason: "space")
            self.refreshOverlayPresentation(bringForward: false)
            wlog("space: active space changed; overlays enforced in assigned spaces")
        }
        spaceRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
