// 专注会话：专注当前 app 工作流（focus shelf）、拉出/放回、
// 会话恢复与外部唤回处理。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func focusSizedWorkSize(originalSize: CGSize, visible: NSRect,
                                    areaRatio: CGFloat, canResize: Bool) -> CGSize {
        focusSizedFrame(pos: .zero, size: originalSize,
                        visible: visible, areaRatio: areaRatio,
                        canResize: canResize).size
    }

    func focusCenteredFrame(pos: CGPoint, size: CGSize,
                                    pid: pid_t, areaRatio: CGFloat) -> NSRect {
        let currentFrame = cocoaFrame(fromAXPosition: pos, size: size)
        guard let screen = screenForCocoaFrame(currentFrame) ?? NSScreen.main ?? NSScreen.screens.first else {
            return currentFrame
        }
        let visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        return focusSizedFrame(pos: pos, size: size,
                               visible: visible, areaRatio: areaRatio,
                               canResize: windowPolicy(for: pid).allowsProxyHorizontalResize)
    }

    func focusShelfReservedFrame(on screen: NSScreen) -> NSRect? {
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let entries = focusSideStackFrames.values.filter { screen.frame.intersects($0) }
        guard !entries.isEmpty else { return nil }
        let shelf = entries.dropFirst().reduce(entries[0]) { $0.union($1) }
        return shelf.insetBy(dx: -8, dy: -12).intersection(visible)
    }

    func centerFocusedWindowForFocusMode(_ win: AXUIElement, pid: pid_t) {
        guard let pos = axPosition(win), let size = axSize(win) else { return }
        var frame = focusCenteredFrame(pos: pos, size: size, pid: pid, areaRatio: 1.0)
        if let screen = screenForCocoaFrame(frame) ?? NSScreen.main ?? NSScreen.screens.first,
           let shelf = focusShelfReservedFrame(on: screen),
           frame.intersects(shelf) {
            var available = screen.visibleFrame.insetBy(dx: 28, dy: 28)
            available.size.height = max(260, shelf.minY - 12 - available.minY)
            frame = focusSizedFrame(pos: pos, size: size,
                                    visible: available,
                                    areaRatio: 1.0,
                                    canResize: windowPolicy(for: pid).allowsProxyHorizontalResize)
        }
        let target = axPosition(fromCocoaFrame: frame)
        if allowsProxyHorizontalResize(win, pid: pid) {
            setAXSize(win, frame.size)
        }
        setAXPosition(win, target)
        raiseAXWindow(win)
        focusAXWindow(win, pid: pid)
        wlog("focus: centered current window pid=\(pid) area=1.0 target=(\(Int(target.x)),\(Int(target.y)) \(Int(frame.width))x\(Int(frame.height)))")
    }

    func pulledOutFocusFrames(state: ShadeState, draggedFrame: NSRect) -> (overlay: NSRect, restore: NSRect) {
        guard let screen = screenForCocoaFrame(draggedFrame)
            ?? screenForCocoaFrame(state.overlay?.frame ?? draggedFrame)
            ?? NSScreen.main ?? NSScreen.screens.first else {
            return (draggedFrame, draggedFrame)
        }
        let visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        let restoreSize = state.originalSize
        let compatibility = windowPolicy(for: state.pid)
        let isResizableWorkWindow = compatibility.allowsProxyHorizontalResize
        let workSize = focusSizedWorkSize(originalSize: restoreSize,
                                          visible: visible,
                                          areaRatio: 0.50,
                                          canResize: isResizableWorkWindow)
        let overlayWidth = isResizableWorkWindow
            ? workSize.width
            : min(max(draggedFrame.width, restoreSize.width, 120), visible.width)
        var restoreFrame = NSRect(x: draggedFrame.minX,
                                  y: draggedFrame.maxY - workSize.height,
                                  width: workSize.width,
                                  height: workSize.height)
        restoreFrame = clampedFrame(restoreFrame, margin: 8)
        let topLeft = axPosition(fromCocoaFrame: restoreFrame)
        let overlayFrame = clampedFrame(cocoaFrame(fromAXPosition: topLeft,
                                                   size: CGSize(width: overlayWidth,
                                                                height: draggedFrame.height)),
                                        margin: 8)
        return (overlayFrame, restoreFrame)
    }

    func focusRestoreFrame(fromOverlayFrame frame: NSRect, restoredSize: CGSize) -> NSRect {
        NSRect(x: frame.minX,
               y: frame.maxY - restoredSize.height,
               width: restoredSize.width,
               height: restoredSize.height)
    }

    func shouldReturnPulledOutOverlayToStack(id: CGWindowID, frame: NSRect) -> Bool {
        guard let stackFrame = focusSideStackFrames[id] else { return false }
        let shelfTopBandMinY = stackFrame.minY - max(24, stackFrame.height * 0.8)
        return frame.maxY >= shelfTopBandMinY
    }

    func restorePulledOutOverlayToStack(id: CGWindowID) -> Bool {
        guard focusPulledOutOverlayIDs.contains(id),
              let overlay = shaded[id]?.overlay,
              let stackFrame = focusSideStackFrames[id] else { return false }
        if var state = shaded[id], let originalSize = focusPulledOutOriginalSizes[id] {
            state.originalSize = originalSize
            shaded[id] = state
        }
        if let proxy = overlay as? NativeProxyOverlayWindow,
           let state = shaded[id] {
            proxy.allowsHorizontalResize = false
            proxy.minSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.maxSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            wlog("focus: restore stack affordance app=\(state.appName) resizable=\(windowPolicy(for: state.pid).allowsProxyHorizontalResize)")
        }
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        applyOverlayPresentation(overlay, bringForward: true)
        arrangeCurrentFocusShelf()
        quietNotice("已放回顶部",
                    log: "focus: return-to-stack id=\(id)")
        return true
    }

    func maybeStageFocusPullOut(id: CGWindowID, frame: NSRect) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway,
              session.entries[id] != nil,
              let stackFrame = focusSideStackFrames[id],
              let state = shaded[id],
              state.appearanceMode == .proxyTitleBar,
              let overlay = state.overlay as? NativeProxyOverlayWindow else { return false }

        let deltaY = stackFrame.minY - frame.minY
        let threshold = max(48, min(96, stackFrame.height * 1.6))
        guard deltaY >= threshold else { return false }

        var updatedState = state
        let pulled = pulledOutFocusFrames(state: state, draggedFrame: frame)
        let compatibility = windowPolicy(for: state.pid)
        if compatibility.allowsProxyHorizontalResize,
           state.originalSize.width > 1,
           state.originalSize.height > 1 {
            focusPulledOutOriginalSizes[id] = focusPulledOutOriginalSizes[id] ?? state.originalSize
            updatedState.originalSize = pulled.restore.size
            shaded[id] = updatedState
        }
        focusPulledOutOverlayIDs.insert(id)
        focusPulledOutRestoreFrames[id] = pulled.restore
        overlay.allowsHorizontalResize = compatibility.allowsProxyHorizontalResize
        overlay.minSize = NSSize(width: overlay.minimumReadableWidth, height: pulled.overlay.height)
        overlay.maxSize = compatibility.allowsProxyHorizontalResize
            ? NSSize(width: 10000, height: pulled.overlay.height)
            : NSSize(width: pulled.overlay.width, height: pulled.overlay.height)
        isProgrammaticOverlayArrangement = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = focusMotionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().setFrame(pulled.overlay, display: true)
        } completionHandler: {
            self.isProgrammaticOverlayArrangement = false
        }
        overlay.level = max(overlayLevel, .floating)
        overlay.orderFrontRegardless()
        syncRestoreJournal(id: id, fromOverlayFrame: pulled.overlay, restoredSize: pulled.restore.size)
        arrangeCurrentFocusShelf(excluding: [id])
        wlog("focus: pull-out stage id=\(id) app=\(state.appName) deltaY=\(Int(deltaY)) overlay=(\(Int(pulled.overlay.minX)),\(Int(pulled.overlay.minY)) \(Int(pulled.overlay.width))x\(Int(pulled.overlay.height))) restore=(\(Int(pulled.restore.minX)),\(Int(pulled.restore.minY)) \(Int(pulled.restore.width))x\(Int(pulled.restore.height)))")
        quietNotice("已拉出，可拖动或调整宽度",
                    log: "focus: staged strip id=\(id) app=\(state.appName)")
        return true
    }

    func rejoinFocusStackAfterShadeIfNeeded(id: CGWindowID, overlay: NSWindow) {
        guard var session = focusSession,
              session.stage == .arrangedAway,
              let stackFrame = focusRejoinStackFrames.removeValue(forKey: id),
              let entry = focusRejoinEntries.removeValue(forKey: id) else { return }

        session.entries[id] = entry
        focusSession = session
        arrangedOverlayFrames[id] = entry.homeOverlayFrame ?? arrangedOverlayFrames[id] ?? overlay.frame
        focusSideStackFrames[id] = stackFrame
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)

        if let proxy = overlay as? NativeProxyOverlayWindow {
            let oldResize = proxy.onResize
            proxy.onResize = nil
            proxy.allowsHorizontalResize = false
            proxy.minSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.maxSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.onResize = oldResize
        }
        applyOverlayPresentation(overlay, bringForward: true)
        arrangeCurrentFocusShelf()
        wlog("focus: rejoin shelf id=\(id)")
        rebuildMenu()
    }

    func shouldAutoJoinFocusShelf(id: CGWindowID, pid: pid_t) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway else { return false }
        if pid == session.focusedPID && id == session.focusedWindowID {
            return false
        }
        return true
    }

    func isFocusShelfMember(id: CGWindowID) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway,
              session.entries[id] != nil else { return false }
        return id != session.focusedWindowID
    }

    func focusTemporaryRevealFrame(for state: ShadeState) -> NSRect {
        let reference = state.overlay?.frame ??
            cocoaFrame(fromAXPosition: axPosition(state.element) ?? state.originalPosition,
                       size: state.originalSize)
        guard let screen = screenForCocoaFrame(reference) ?? NSScreen.main ?? NSScreen.screens.first else {
            return reference
        }
        var visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        if let shelf = focusShelfReservedFrame(on: screen) {
            visible.size.height = max(260, shelf.minY - 12 - visible.minY)
        }
        return focusSizedFrame(pos: state.originalPosition,
                               size: state.originalSize,
                               visible: visible,
                               areaRatio: 0.50,
                               canResize: windowPolicy(for: state.pid).allowsProxyHorizontalResize)
    }

    func revealFocusShelfMemberFromOutside(id: CGWindowID, state: ShadeState, reason: String) {
        let frame = focusTemporaryRevealFrame(for: state)
        var workingState = state
        workingState.originalSize = frame.size
        let pos = axPosition(fromCocoaFrame: frame)
        let rejoinEntry = FocusSessionEntry(
            id: id,
            wasAlreadyShaded: focusSession?.entries[id]?.wasAlreadyShaded ?? false,
            homeOverlayFrame: arrangedOverlayFrames[id] ?? state.overlay?.frame,
            pid: state.pid,
            appName: state.appName
        )
        let win = restoreWindow(workingState, to: pos)
        bringRestoredWindowToFront(win, pid: state.pid, reason: "focus external reveal id=\(id) \(reason)")
        pinRestoredWindow(workingState, to: pos, reason: "focus external reveal id=\(id) \(reason)")
        forceCleanup(id, preserveFocusEntry: true)
        focusRejoinEntries[id] = rejoinEntry
        wlog("focus: external reveal centered id=\(id) app=\(state.appName) reason=\(reason) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
    }

    func joinFocusShelfAfterShadeIfNeeded(id: CGWindowID, overlay: NSWindow) {
        guard shouldAutoJoinFocusShelf(id: id, pid: shaded[id]?.pid ?? 0),
              var session = focusSession,
              let state = shaded[id] else { return }

        let existingEntry = session.entries[id]
        let entry = FocusSessionEntry(
            id: id,
            wasAlreadyShaded: existingEntry?.wasAlreadyShaded ?? false,
            homeOverlayFrame: existingEntry?.homeOverlayFrame ?? overlay.frame,
            pid: state.pid,
            appName: state.appName
        )

        session.entries[id] = entry
        focusSession = session
        arrangedOverlayFrames[id] = entry.homeOverlayFrame ?? overlay.frame
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)

        if let proxy = overlay as? NativeProxyOverlayWindow {
            let oldResize = proxy.onResize
            proxy.onResize = nil
            proxy.allowsHorizontalResize = false
            proxy.onResize = oldResize
        }

        arrangeCurrentFocusShelf()
        wlog("focus: auto-join shelf id=\(id) app=\(state.appName)")
    }

    func noteUserMovedOverlay(id: CGWindowID, frame: NSRect) {
        guard !isProgrammaticOverlayArrangement else { return }
        if focusPulledOutOverlayIDs.contains(id) {
            if shouldReturnPulledOutOverlayToStack(id: id, frame: frame) {
                _ = restorePulledOutOverlayToStack(id: id)
                return
            }
            if let state = shaded[id] {
                focusPulledOutRestoreFrames[id] = focusRestoreFrame(fromOverlayFrame: frame,
                                                                     restoredSize: state.originalSize)
            }
            syncRestoreJournal(id: id, fromOverlayFrame: frame)
            return
        }
        if maybeStageFocusPullOut(id: id, frame: frame) {
            return
        }
        let hadArrangedFrame = arrangedOverlayFrames[id] != nil
        syncRestoreJournal(id: id, fromOverlayFrame: frame)
        arrangedOverlayFrames.removeValue(forKey: id)
        if hadArrangedFrame {
            rebuildMenu()
        }
    }

    func removeFocusSessionEntry(_ id: CGWindowID) {
        guard var session = focusSession else { return }
        session.entries.removeValue(forKey: id)
        focusSession = session.entries.isEmpty ? nil : session
    }
    func focusCurrentAppCycle() {
        guard ensureAccessibility() else {
            showPermissionOnboardingIfNeeded(force: true)
            quietNotice("需要权限", log: "focus: 无辅助功能权限")
            return
        }

        guard appearanceMode == .proxyTitleBar else {
            arrangeShadedWindows()
            return
        }

        if let session = focusSession {
            switch session.stage {
            case .arrangedAway:
                restoreFocusBarsHome(session)
            case .barsRestoredHome:
                restoreFocusSession(session)
            }
            return
        }

        startFocusCurrentAppSession()
    }

    func focusedApplicationForFocusSession() -> NSRunningApplication? {
        if let win = focusedWindow() {
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            if pid != ProcessInfo.processInfo.processIdentifier {
                return runningApp(pid: pid)
            }
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return app
    }

    func startFocusCurrentAppSession() {
        guard let focusedApp = focusedApplicationForFocusSession() else {
            quietNotice("没有当前 App", log: "focus: no focused app")
            return
        }

        let focusedPID = focusedApp.processIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let focusedWinForCenter: AXUIElement? = {
            guard let win = focusedWindow() else { return nil }
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            return pid == focusedPID ? win : nil
        }()
        let focusedWindowID = focusedWinForCenter.flatMap { windowID(of: $0) }
        var entries: [CGWindowID: FocusSessionEntry] = [:]
        var createdCount = 0

        for (id, state) in shaded where state.pid != focusedPID {
            entries[id] = FocusSessionEntry(
                id: id,
                wasAlreadyShaded: true,
                homeOverlayFrame: state.overlay.map { restoreReferenceFrame(id: id, overlay: $0) },
                pid: state.pid,
                appName: state.appName
            )
        }

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != focusedPID, pid != selfPID else { continue }
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            if windowPolicy(for: pid).delegatesNativeShade {
                wlog("focus: skip native-shade app=\(appDisplayName(pid: pid)) pid=\(pid)")
                continue
            }

            for win in appWindows(pid: pid) {
                guard let id = windowID(of: win), shaded[id] == nil else { continue }
                let beforeIDs = Set(shaded.keys)
                shade(win, id, options: focusShadeOptions)
                guard !beforeIDs.contains(id),
                      let state = shaded[id],
                      let overlay = state.overlay else { continue }
                createdCount += 1
                entries[id] = FocusSessionEntry(
                    id: id,
                    wasAlreadyShaded: false,
                    homeOverlayFrame: overlay.frame,
                    pid: pid,
                    appName: state.appName
                )
            }
        }

        let focusIDs = Set(entries.keys)
        let arrangeEntries = focusIDs.compactMap { id -> (CGWindowID, ShadeState, NSWindow)? in
            guard let state = shaded[id], let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }

        guard !arrangeEntries.isEmpty else {
            quietNotice("没有可收起的窗口", log: "focus: no foldable windows outside \(focusedPID)")
            return
        }

        for entry in entries.values {
            if let home = entry.homeOverlayFrame {
                arrangedOverlayFrames[entry.id] = arrangedOverlayFrames[entry.id] ?? home
            }
        }

        focusSession = FocusSession(focusedPID: focusedPID,
                                    focusedAppName: focusedApp.localizedName ?? appDisplayName(pid: focusedPID),
                                    focusedWindowID: focusedWindowID,
                                    stage: .arrangedAway,
                                    entries: entries)
        arrangeShadedEntries(arrangeEntries, reason: "focus")
        if createdCount > 0 {
            playFoldSound()
        }
        bringFocusedAppToFront(focusedApp)
        if let focusedWinForCenter {
            centerFocusedWindowForFocusMode(focusedWinForCenter, pid: focusedPID)
        }
        quietNotice("专注：\(focusedApp.localizedName ?? "当前 App")",
                    log: "focus: start app=\(focusedApp.localizedName ?? "?") pid=\(focusedPID) entries=\(entries.count) created=\(createdCount) fastProxy=true")
    }

    func bringFocusedAppToFront(_ app: NSRunningApplication) {
        app.activate()
    }

    func restoreFocusBarsHome(_ session: FocusSession) {
        let ids = Set(session.entries.keys)
        _ = restoreArrangedOverlayFrames(ids: ids)
        var updated = session
        updated.stage = .barsRestoredHome
        focusSession = updated
        quietNotice("卷帘条已回原位",
                    log: "focus: bars home app=\(session.focusedAppName) entries=\(session.entries.count)")
        rebuildMenu()
    }

    func restoreFocusSession(_ session: FocusSession) {
        let ids = Set(session.entries.keys)
        _ = restoreArrangedOverlayFrames(ids: ids)

        let createdIDs = session.entries.values
            .filter { !$0.wasAlreadyShaded }
            .map(\.id)

        let playSound = soundEnabled && !createdIDs.isEmpty
        suppressUnshadeSounds = true
        withMenuRebuildSuppressed {
            for id in createdIDs {
                unshade(id)
            }
        }
        suppressUnshadeSounds = false
        if playSound {
            playUnfoldSound()
        }

        focusSession = nil
        focusRejoinStackFrames.removeAll()
        focusRejoinEntries.removeAll()
        quietNotice("已恢复专注前状态",
                    log: "focus: restore app=\(session.focusedAppName) unfolded=\(createdIDs.count)")
        rebuildMenu()
    }
}
