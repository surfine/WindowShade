// 折叠出口与交通灯：展开恢复、清理、交通灯动作转发、QuickLook 特殊处理。
// 作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func unshadeReturningElement(_ id: CGWindowID, playSound: Bool = true,
                                         pinAfterRestore: Bool = true) -> AXUIElement? {
        guard shaded[id] != nil else { return nil }
        markShadeLifecycle(id: id, .restoring, reason: "unshade")
        transitionOperationState(id: id, to: .restoring, reason: "unshade")
        guard let state = shaded.removeValue(forKey: id) else { return nil }
        let shouldRememberFocusRejoin = focusPulledOutOverlayIDs.contains(id) && focusSession?.stage == .arrangedAway
        let rejoinEntry = shouldRememberFocusRejoin ? focusSession?.entries[id] : nil
        let rejoinStackFrame = shouldRememberFocusRejoin ? focusSideStackFrames[id] : nil
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        privateAlphaOriginalValues.removeValue(forKey: id)
        pendingSpaceReturns.removeValue(forKey: id)
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        if !shouldRememberFocusRejoin {
            removeFocusSessionEntry(id)
        }
        if let rejoinEntry, let rejoinStackFrame {
            focusRejoinEntries[id] = rejoinEntry
            focusRejoinStackFrames[id] = rejoinStackFrame
        }
        accessibilityActionTargets.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)                          // 先停掉监听，避免下面的恢复动作反过来触发自己
        // 折叠条可能被拖动过 → 窗口在折叠条「当前」位置展开（标题栏带着窗口走）
        let pos: CGPoint
        if let overlay = state.overlay {
            pos = axPosition(fromCocoaFrame: restoreReferenceFrame(id: id, overlay: overlay))
            dismissOverlay(overlay)
        } else {
            pos = axPosition(state.element) ?? state.originalPosition
        }
        if state.hide == .quickLookClosed {
            if let url = state.quickLookReopenURL, reopenQuickLookPreview(url: url) {
                wlog("quicklook: reopened via qlmanage id=\(id) path=\(url.path)")
            } else if reopenQuickLookFromFinderSelection(pid: state.pid) {
                wlog("quicklook: reopened via Finder Space fallback id=\(id) title=\(state.title)")
            } else {
                wlog("quicklook: reopen unavailable id=\(id) title=\(state.title)")
            }
            rebuildMenu()
            if playSound && !suppressUnshadeSounds {
                playUnfoldSound()
            }
            transitionOperationState(id: id, to: .normal, reason: "unshade-quicklook")
            return nil
        }
        let restoredElement = restoreWindow(state, to: pos)
        bringRestoredWindowToFront(restoredElement, pid: state.pid, reason: "unshade id=\(id)")
        if pinAfterRestore {
            pinRestoredWindow(state, to: pos, reason: "unshade id=\(id)")
        } else {
            cancelRestorePin(for: id)
        }
        transitionOperationState(id: id, to: .normal, reason: "unshade")
        rebuildMenu()
        if playSound && !suppressUnshadeSounds {
            playUnfoldSound()
        }
        return restoredElement
    }
    @discardableResult
    func unshade(_ id: CGWindowID) -> Bool {
        unshadeReturningElement(id) != nil
    }
    func forceCleanup(_ id: CGWindowID, preserveFocusEntry: Bool = false) {
        guard shaded[id] != nil else { return }
        markShadeLifecycle(id: id, .cleaned, reason: "forceCleanup")
        guard let state = shaded.removeValue(forKey: id) else { return }
        transitionOperationState(id: id, to: .normal, reason: "forceCleanup")
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        privateAlphaOriginalValues.removeValue(forKey: id)
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        if !preserveFocusEntry {
            removeFocusSessionEntry(id)
        }
        accessibilityActionTargets.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)
        if let overlay = state.overlay { dismissOverlay(overlay) }
        rebuildMenu()
    }
    func removeProxyForAction(_ id: CGWindowID, state: ShadeState,
                                      stage: ShadeLifecycleStage, reason: String) {
        markShadeLifecycle(id: id, stage, reason: reason)
        transitionOperationState(id: id, to: .normal, reason: "removeProxy")
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        removeFocusSessionEntry(id)
        accessibilityActionTargets.removeValue(forKey: id)
        shaded.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)
        if let overlay = state.overlay { dismissOverlay(overlay) }
        rebuildMenu()
    }
    func removeProxyForForwardedAction(_ id: CGWindowID, state: ShadeState) {
        removeProxyForAction(id, state: state, stage: .forwarded, reason: "traffic-light-forward")
    }
    func quickLookProcessHint(pid: pid_t) -> Bool {
        let bundle = appBundleID(pid: pid).lowercased()
        let name = appDisplayName(pid: pid).lowercased()
        return bundle == "com.apple.finder" ||
            bundle.contains("quicklook") ||
            bundle.contains("qlmanage") ||
            name.contains("finder") ||
            name.contains("quicklook") ||
            name.contains("quick look") ||
            name.contains("qlmanage") ||
            name.contains("快速查看")
    }
    func windowLooksLikeQuickLookTarget(_ win: AXUIElement, pid: pid_t,
                                                expectedTitle: String) -> Bool {
        if proxyTrafficLightConfiguration(of: win, pid: pid).style == .quickLook {
            return true
        }
        let hasClose = axButtonFrame(win, kAXCloseButtonAttribute as String) != nil
        let hasMinimize = axButtonFrame(win, kAXMinimizeButtonAttribute as String) != nil
        let hasFullScreenish = axButtonFrame(win, kAXFullScreenButtonAttribute as String) != nil ||
            axButtonFrame(win, kAXZoomButtonAttribute as String) != nil ||
            isAXAttributeSettable(win, axFullScreenAttribute)
        guard hasClose, hasFullScreenish, !hasMinimize, firstToolbar(win) == nil else { return false }
        if quickLookProcessHint(pid: pid) { return true }

        let cleanExpected = cleanDisplayTitle(expectedTitle).lowercased()
        let cleanTitle = cleanDisplayTitle(axTitle(win)).lowercased()
        return !cleanExpected.isEmpty &&
            (cleanTitle == cleanExpected ||
             cleanTitle.contains(cleanExpected) ||
             cleanExpected.contains(cleanTitle))
    }
    func quickLookWindowCandidates(preferredPID: pid_t, title: String) -> [(pid: pid_t, win: AXUIElement)] {
        let cleanTitle = cleanDisplayTitle(title)
        var pids: [pid_t] = [preferredPID]
        for app in NSWorkspace.shared.runningApplications {
            if quickLookProcessHint(pid: app.processIdentifier) {
                pids.append(app.processIdentifier)
            }
        }
        let cgWindows = WindowListCache.shared.onScreenWindows()
        for info in cgWindows {
            let ownerName = ((info[kCGWindowOwnerName as String] as? String) ?? "").lowercased()
            let windowName = cleanDisplayTitle(cgWindowName(info)).lowercased()
            let titleHint = !cleanTitle.isEmpty && !windowName.isEmpty &&
                (windowName == cleanTitle.lowercased() ||
                 windowName.contains(cleanTitle.lowercased()) ||
                 cleanTitle.lowercased().contains(windowName))
            guard ownerName.contains("quicklook") ||
                    ownerName.contains("quick look") ||
                    ownerName.contains("qlmanage") ||
                    ownerName.contains("finder") ||
                    ownerName.contains("快速查看") ||
                    titleHint,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            pids.append(ownerPID.int32Value)
        }

        var seen = Set<Int32>()
        var candidates: [(pid: pid_t, win: AXUIElement, score: Int)] = []
        for pid in pids where seen.insert(pid).inserted {
            for win in appWindows(pid: pid) {
                guard windowLooksLikeQuickLookTarget(win, pid: pid, expectedTitle: title) else { continue }
                var score = pid == preferredPID ? 0 : 10
                if quickLookProcessHint(pid: pid) { score -= 6 }
                let candidateTitle = cleanDisplayTitle(axTitle(win))
                if !cleanTitle.isEmpty && !candidateTitle.isEmpty {
                    if candidateTitle == cleanTitle {
                        score -= 30
                    } else if candidateTitle.contains(cleanTitle) || cleanTitle.contains(candidateTitle) {
                        score -= 15
                    }
                }
                if let size = axSize(win), size.width > 40, size.height > 40 {
                    score -= 4
                }
                candidates.append((pid, win, score))
            }
        }

        return candidates.sorted { $0.score < $1.score }.map { ($0.pid, $0.win) }
    }
    func reopenQuickLookForProxyFullScreen(state: ShadeState, id: CGWindowID) -> Bool {
        if let url = state.quickLookReopenURL, reopenQuickLookPreview(url: url) {
            wlog("quicklook fullscreen: reopen via qlmanage id=\(id) path=\(url.path)")
            return true
        }
        if reopenQuickLookFromFinderSelection(pid: state.pid) {
            wlog("quicklook fullscreen: reopen via Finder Space id=\(id) title=\(state.title)")
            return true
        }
        wlog("quicklook fullscreen: reopen unavailable id=\(id) title=\(state.title)")
        return false
    }
    func clickQuickLookVisualFullScreenButton(_ win: AXUIElement, pid: pid_t,
                                                      id: CGWindowID, attempt: Int) -> Bool {
        let offsets: [CGFloat] = [28, 26, 30, 24, 32]
        let offset = offsets[min(attempt, offsets.count - 1)]
        let point: CGPoint
        if let close = axButtonFrame(win, kAXCloseButtonAttribute as String) {
            point = CGPoint(x: close.midX + offset, y: close.midY)
            wlog("quicklook fullscreen: visual point from close id=\(id) pid=\(pid) attempt=\(attempt) close=(\(Int(close.minX)),\(Int(close.minY)) \(Int(close.width))x\(Int(close.height))) offset=\(Int(offset))")
        } else if let pos = axPosition(win), let size = axSize(win),
                  size.width > 80, size.height > 30 {
            let fallbackOffsets: [CGFloat] = [50, 48, 52, 46, 54]
            point = CGPoint(x: pos.x + fallbackOffsets[min(attempt, fallbackOffsets.count - 1)],
                            y: pos.y + 20)
            wlog("quicklook fullscreen: visual point from window id=\(id) pid=\(pid) attempt=\(attempt) pos=(\(Int(pos.x)),\(Int(pos.y)))")
        } else {
            return false
        }

        return humanClickAXPoint(point,
                                 reason: "quicklook-visual-fullscreen",
                                 logLabel: "quicklook-visual-fullscreen id=\(id) pid=\(pid) attempt=\(attempt)")
    }
    func triggerQuickLookFullScreen(_ win: AXUIElement, pid: pid_t,
                                            id: CGWindowID, attempt: Int) -> Bool {
        if clickQuickLookVisualFullScreenButton(win, pid: pid, id: id, attempt: attempt) {
            wlog("quicklook fullscreen: visual click scheduled id=\(id) pid=\(pid) attempt=\(attempt)")
            return true
        }

        if isAXAttributeSettable(win, axFullScreenAttribute),
           AXUIElementSetAttributeValue(win, axFullScreenAttribute as CFString, kCFBooleanTrue) == .success {
            wlog("quicklook fullscreen: AXFullScreen set id=\(id) pid=\(pid) attempt=\(attempt)")
            return true
        }

        let attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
        for attr in attrs {
            if pressAXButton(win, attr) {
                wlog("quicklook fullscreen: AXPress attr=\(attr) id=\(id) pid=\(pid) attempt=\(attempt)")
                return true
            }
        }
        for attr in attrs {
            if clickAXButton(win, attr) {
                wlog("quicklook fullscreen: pointer click attr=\(attr) id=\(id) pid=\(pid) attempt=\(attempt)")
                return true
            }
        }
        return false
    }
    func verifyQuickLookFullScreenOrSendShortcut(_ win: AXUIElement, pid: pid_t,
                                                         id: CGWindowID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            if axBoolAttribute(win, axFullScreenAttribute) {
                wlog("quicklook fullscreen: verified after trigger id=\(id) pid=\(pid) attempt=\(attempt)")
                return
            }

            runningApp(pid: pid)?.activate(options: [])
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if attempt < 4,
               self.clickQuickLookVisualFullScreenButton(win, pid: pid, id: id, attempt: attempt + 1) {
                wlog("quicklook fullscreen: retry visual click id=\(id) pid=\(pid) attempt=\(attempt + 1)")
                self.verifyQuickLookFullScreenOrSendShortcut(win, pid: pid, id: id, attempt: attempt + 1)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                runningApp(pid: pid)?.activate(options: [])
                raiseAXWindow(win)
                focusAXWindow(win, pid: pid)
                pressFullScreenShortcut()
                wlog("quicklook fullscreen: shortcut fallback sent id=\(id) pid=\(pid) attempt=\(attempt)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) {
                let ok = axBoolAttribute(win, axFullScreenAttribute)
                wlog("quicklook fullscreen: shortcut verification id=\(id) pid=\(pid) ok=\(ok)")
            }
        }
    }
    func openQuickLookFullScreenFromProxy(state: ShadeState, id: CGWindowID) {
        let delays: [TimeInterval] = [0.08, 0.18, 0.32, 0.55, 0.85, 1.20]

        func attempt(_ index: Int) {
            guard index < delays.count else {
                wlog("quicklook fullscreen: unavailable; no QuickLook target id=\(id)")
                return
            }

            if let target = quickLookWindowCandidates(preferredPID: state.pid, title: state.title).first {
                runningApp(pid: target.pid)?.activate(options: [])
                raiseAXWindow(target.win)
                focusAXWindow(target.win, pid: target.pid)
                if triggerQuickLookFullScreen(target.win, pid: target.pid, id: id, attempt: index) {
                    verifyQuickLookFullScreenOrSendShortcut(target.win, pid: target.pid, id: id, attempt: index)
                    return
                }
                wlog("quicklook fullscreen: target not ready id=\(id) attempt=\(index)")
            } else {
                wlog("quicklook fullscreen: waiting for reopened window id=\(id) attempt=\(index)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) {
                attempt(index + 1)
            }
        }

        attempt(0)
    }
    func handleQuickLookTrafficLight(_ action: TrafficAction, id: CGWindowID, state: ShadeState) {
        switch action {
        case .close:
            removeProxyForAction(id, state: state, stage: .cleaned, reason: "quicklook-proxy-close")
            wlog("quicklook proxy: close removed proxy id=\(id)")
        case .fullScreen, .zoom:
            removeProxyForAction(id, state: state, stage: .restoring, reason: "quicklook-proxy-fullscreen")
            guard reopenQuickLookForProxyFullScreen(state: state, id: id) else { return }
            openQuickLookFullScreenFromProxy(state: state, id: id)
        case .minimize:
            removeProxyForAction(id, state: state, stage: .cleaned, reason: "quicklook-proxy-ignore-minimize")
            wlog("quicklook proxy: ignore minimize id=\(id)")
        }
    }
    func handleTrafficLight(_ action: TrafficAction, _ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        if state.hide == .quickLookClosed {
            handleQuickLookTrafficLight(action, id: id, state: state)
            return
        }
        let f = restoreReferenceFrame(id: id, overlay: overlay)
        let pos = axPosition(fromCocoaFrame: f)
        switch action {
        case .close:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos) // 先让真窗口可见可达
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .close)
        case .minimize:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos) // 回到原处
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .minimize)
        case .zoom:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos)
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .zoom)
        case .fullScreen:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos)
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .fullScreen)
        }
    }
    func handleClassicAction(_ action: ClassicAction, _ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        let f = restoreReferenceFrame(id: id, overlay: overlay)
        let pos = axPosition(fromCocoaFrame: f)
        switch action {
        case .close:
            restoreWindow(state, to: pos)
            pressAXButton(state.element, kAXCloseButtonAttribute as String)
            forceCleanup(id)
        case .zoom:
            let el = state.element
            unshade(id)
            pressAXButton(el, kAXZoomButtonAttribute as String)
        case .expand:
            unshade(id)
        }
    }
}
