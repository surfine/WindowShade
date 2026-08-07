// 覆盖层展示与空间不变量：卷帘条窗口的呈现/销毁、Space 归属与兜底回切、
// 外部唤回清理。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    var overlayLevel: NSWindow.Level {
        floatingOnTop ? .floating : .normal
    }

    func overlayLevel(for overlay: NSWindow) -> NSWindow.Level {
        guard !floatingOnTop,
              let entry = shaded.first(where: { $0.value.overlay === overlay }) else {
            return overlayLevel
        }
        let id = entry.key
        if isFocusShelfMember(id: id) || focusPulledOutOverlayIDs.contains(id) {
            return .floating
        }
        return .normal
    }

    var overlayAlpha: CGFloat {
        translucent ? shadeTranslucentAlpha : 1
    }

    func shadedEntry(for overlay: NSWindow) -> (CGWindowID, ShadeState)? {
        shaded.first { $0.value.overlay === overlay }
    }

    func applyOverlayPresentation(_ overlay: NSWindow, bringForward: Bool) {
        if let (id, state) = shadedEntry(for: overlay),
           !enforceOverlaySpaceInvariant(id: id, state: state, reason: "apply-presentation") {
            return
        }
        overlay.level = overlayLevel(for: overlay)
        overlay.alphaValue = overlayAlpha
        if bringForward {
            overlay.orderFrontRegardless()
        }
    }

    func sourceSpaceIsActive(_ state: ShadeState) -> Bool {
        guard let sourceSpaceID = state.sourceSpaceID,
              let sourceDisplayID = state.sourceDisplayID,
              let activeSpaceID = PrivateSLSWindowMover.shared.currentSpace(displayID: sourceDisplayID) else {
            return true
        }
        return activeSpaceID == sourceSpaceID
    }

    func scheduleSourceSpaceReturnIfNeeded(id: CGWindowID, state: ShadeState) {
        guard hideMethodCanTriggerSpaceJump(state.hide),
              let displayID = state.sourceDisplayID,
              let sourceSpaceID = state.sourceSpaceID else { return }

        // 保险丝：焦点交接（handOffFocusBeforeHiding）负责预防，这里负责兜底补偿。
        // 检测必须快于 Space 滑动动画（~300ms）：密集轮询 + SLSManagedDisplay-
        // SetCurrentSpace 瞬时切换（无滑动动画），在动画完成前拉回，把"跳走再
        // 滑回来"的双重闪动压缩成一瞬。每次检查只是一个 WindowServer 读，极廉价。
        // 只覆盖系统级联跳变的窗口期：超过 ~0.55s 的 Space 差异更可能是用户自己
        // 的切换动作（折叠后主动去别的 Space），旧实现 2.5s 内会把用户切走拽回。
        pendingSpaceReturns[id] = PendingSpaceReturn(displayID: displayID,
                                                     sourceSpaceID: sourceSpaceID,
                                                     deadline: Date().addingTimeInterval(0.8))
        wlog("space: scheduled return guard id=\(id) sid=\(sourceSpaceID)")

        for delay in [0.05, 0.1, 0.15, 0.22, 0.3, 0.42, 0.55] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.restorePendingSourceSpaceIfNeeded(id: id, reason: "post-shade-\(String(format: "%.2f", delay))")
            }
        }
    }

    func restorePendingSourceSpacesIfNeeded(reason: String) {
        for id in Array(pendingSpaceReturns.keys) {
            restorePendingSourceSpaceIfNeeded(id: id, reason: reason)
        }
    }

    func restorePendingSourceSpaceIfNeeded(id: CGWindowID, reason: String) {
        guard let request = pendingSpaceReturns[id] else { return }
        guard Date() <= request.deadline,
              let state = shaded[id],
              state.lifecycleStage == .folded,
              hideMethodCanTriggerSpaceJump(state.hide) else {
            if let activeSpaceID = PrivateSLSWindowMover.shared.currentSpace(displayID: request.displayID),
               activeSpaceID != request.sourceSpaceID {
                wlog("space: return guard expired id=\(id) active=\(activeSpaceID) source=\(request.sourceSpaceID) reason=\(reason)")
            }
            pendingSpaceReturns.removeValue(forKey: id)
            return
        }

        let mover = PrivateSLSWindowMover.shared
        guard let activeSpaceID = mover.currentSpace(displayID: request.displayID) else {
            wlog("space: return guard cannot read active space id=\(id) sid=\(request.sourceSpaceID) reason=\(reason)")
            return
        }
        guard activeSpaceID != request.sourceSpaceID else { return }

        if mover.setCurrentSpace(displayID: request.displayID, sid: request.sourceSpaceID) {
            // parking 策略（空 Space 折叠）下系统级联仍可能跳变，此处兜回属预期；
            // 若前面的 handoff 日志是 same-app/top-window 策略则需排查预防为何失效。
            wlog("space: return guard fired sid=\(request.sourceSpaceID) from=\(activeSpaceID) id=\(id) reason=\(reason)")
            // 与 overlay 可见性绑定：跳回后立即校正 overlay 归属与显隐。
            if let state = shaded[id] {
                _ = enforceOverlaySpaceInvariant(id: id, state: state, reason: "space-return-guard")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshOverlayPresentation(bringForward: false)
            }
        } else {
            wlog("space: return failed id=\(id) from=\(activeSpaceID) to=\(request.sourceSpaceID) reason=\(reason)")
        }
    }

    func hideMethodCanTriggerSpaceJump(_ hide: HideMethod) -> Bool {
        switch hide {
        case .hidden, .minimized:
            return true
        case .none, .offscreen, .privateOffscreen, .privateAlpha, .ownWindowOrderedOut, .quickLookClosed:
            return false
        }
    }

    @discardableResult
    func enforceOverlaySpaceInvariant(id: CGWindowID,
                                              state: ShadeState,
                                              reason: String) -> Bool {
        guard let overlay = state.overlay,
              let overlayID = state.overlayID,
              let sourceSpaceID = state.sourceSpaceID else { return true }

        let mover = PrivateSLSWindowMover.shared
        let overlaySpaceID = mover.windowSpace(id: overlayID)
        if overlaySpaceID == nil {
            let active = sourceSpaceIsActive(state)
            if active {
                if !overlay.isVisible {
                    overlay.alphaValue = 0
                    overlay.orderFrontRegardless()
                    revealPreparedOverlay(overlay)
                }
                wlog("space: overlay space unresolved but source active id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
                return true
            }
            overlay.orderOut(nil)
            wlog("space: overlay hidden while source inactive and overlay space unresolved id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
            return false
        }

        if overlaySpaceID == sourceSpaceID {
            let active = sourceSpaceIsActive(state)
            if active, !overlay.isVisible {
                overlay.alphaValue = 0
                overlay.orderFrontRegardless()
                if mover.windowSpace(id: overlayID) != sourceSpaceID {
                    _ = mover.moveWindow(id: overlayID, toSpace: sourceSpaceID)
                }
                revealPreparedOverlay(overlay)
                wlog("space: overlay restored on source space id=\(overlayID) source=\(id) reason=\(reason)")
            } else if !active, cgWindowIsCurrentlyOnScreen(overlayID) {
                overlay.orderOut(nil)
                wlog("space: overlay hidden off source active space id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
            }
            return active
        }

        if mover.moveWindow(id: overlayID, toSpace: sourceSpaceID) {
            wlog("space: corrected overlay id=\(overlayID) source=\(id) from=\(overlaySpaceID.map(String.init) ?? "-") to=\(sourceSpaceID) reason=\(reason)")
            return sourceSpaceIsActive(state)
        }

        overlay.orderOut(nil)
        wlog("space: invariant hid overlay id=\(overlayID) source=\(id) overlaySpace=\(overlaySpaceID.map(String.init) ?? "-") expected=\(sourceSpaceID) reason=\(reason)")
        return false
    }

    func cleanupProxyIfSourceWindowVisible(id: CGWindowID, state: ShadeState,
                                                   reason: String,
                                                   onScreenWindowIDs: Set<CGWindowID>? = nil) -> Bool {
        guard state.hide != .quickLookClosed,
              let pos = axPosition(state.element),
              let size = axSize(state.element),
              sourceWindowLooksUserVisible(state: state, pos: pos, size: size,
                                           onScreenWindowIDs: onScreenWindowIDs) else {
            return false
        }

        wlog("proxy: source visible; cleanup id=\(id) app=\(state.appName) reason=\(reason)")
        forceCleanup(id)
        return true
    }

    func prepareOverlayWindowForSpaceAssignment(_ overlay: NSWindow) {
        overlay.level = overlayLevel
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
    }

    func revealPreparedOverlay(_ overlay: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = overlayAlpha
        }
    }

    func dismissOverlay(_ overlay: NSWindow) {
        let windowNumber = overlay.windowNumber
        overlay.ignoresMouseEvents = true
        overlay.alphaValue = 0
        overlay.orderOut(nil)
        if let proxy = overlay as? NativeProxyOverlayWindow {
            proxy.closeProgrammatically()
        } else if let strip = overlay as? OverlayWindow {
            ShadeStripPool.shared.recycle(strip)
        } else {
            overlay.close()
        }
        wlog("overlay: dismissed window=\(windowNumber)")
    }

    func refreshOverlayPresentation(bringForward: Bool = false) {
        let onScreenIDs = currentOnScreenWindowIDs()
        for (id, state) in Array(shaded) {
            if cleanupProxyIfSourceWindowVisible(id: id, state: state,
                                                 reason: "refresh-presentation",
                                                 onScreenWindowIDs: onScreenIDs) {
                continue
            }
            if let overlay = state.overlay {
                guard enforceOverlaySpaceInvariant(id: id, state: state, reason: "refresh-presentation") else {
                    continue
                }
                applyOverlayPresentation(overlay, bringForward: bringForward)
            }
        }
        if let active = activePreview, active.trigger == .titlebarPeek {
            applyOverlayPresentation(active.window, bringForward: bringForward)
        }
    }

    func visibleFrame(for frame: NSRect) -> NSRect {
        (screenForCocoaFrame(frame)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame)
    }

    func visibleFrame(for frame: NSRect, preferredDisplayID: CGDirectDisplayID?) -> NSRect {
        screenForDisplayID(preferredDisplayID)?.visibleFrame ?? visibleFrame(for: frame)
    }

    func clampedFrame(_ frame: NSRect, margin: CGFloat = 8,
                              preferredDisplayID: CGDirectDisplayID? = nil) -> NSRect {
        var visible = visibleFrame(for: frame, preferredDisplayID: preferredDisplayID).insetBy(dx: margin, dy: margin)
        if visible.width <= 1 || visible.height <= 1 {
            visible = visibleFrame(for: frame, preferredDisplayID: preferredDisplayID)
        }

        var result = frame
        if result.width <= visible.width {
            result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        } else {
            result.origin.x = visible.minX
        }
        if result.height <= visible.height {
            result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        } else {
            result.origin.y = visible.minY
        }
        return result
    }
}
