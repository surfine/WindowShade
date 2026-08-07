// 折叠入口：聚焦窗口解析、折叠计划、截图与主 shade 事务。
// 作为 AppDelegate 扩展实现；隐藏/恢复/验证见 FoldTransaction。

import Cocoa
import ScreenCaptureKit

extension AppDelegate {
    func retargetToActiveSpaceWindow(pid: pid_t) -> (AXUIElement, CGWindowID)? {
        let onScreen = WindowListCache.shared.onScreenWindows()
        // 在屏列表自前向后有序：取该 app 第一个不透明的 layer-0 窗口（排除我们的卷帘条）。
        guard let candidate = onScreen.first(where: { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = cgWindowBounds(info), bounds.width > 1, bounds.height > 1,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  !overlayIDs.contains(CGWindowID(number.uint32Value)) else { return false }
            return true
        }),
        let number = candidate[kCGWindowNumber as String] as? NSNumber,
        let bounds = cgWindowBounds(candidate) else { return nil }

        var best: (win: AXUIElement, delta: CGFloat)?
        for win in appWindows(pid: pid) {
            guard let pos = axPosition(win), let size = axSize(win) else { continue }
            let delta = frameDistance(CGRect(origin: pos, size: size), bounds)
            if delta <= 96, best == nil || delta < best!.delta {
                best = (win, delta)
            }
        }
        guard let found = best?.win else { return nil }
        return (found, CGWindowID(number.uint32Value))
    }
    func toggle() {
        guard ensureAccessibility() else {
            showPermissionOnboardingIfNeeded(force: true)
            quietNotice("需要权限", log: "toggle: 无辅助功能权限")
            return
        }
        if let shadedID = currentShadedOverlayID() {
            wlog("toggle: current shaded overlay id=\(shadedID) → unshade")
            unshade(shadedID)
            return
        }
        guard let focusedWin = focusedWindow(), let focusedID = windowID(of: focusedWin) else {
            quietNotice("没有可折叠窗口", log: "toggle: 取不到聚焦窗口/windowID")
            return
        }
        var win = focusedWin
        var id = focusedID
        if isDesktopWidgetWindow(id: id) {
            quietNotice("桌面小组件不参与折叠", log: "toggle: reject desktop widget id=\(id)")
            return
        }
        // 聚焦窗口不在当前 Space（已折叠的除外——它们的真实窗口本来就不在屏上，
        // 要走下面的 unshade 分支）：改折该 app 在当前 Space 的最前窗口；
        // 一个都没有就不折叠，避免"折叠当前窗口跑到另一个 Space"。
        if shaded[id] == nil, !cgWindowIsCurrentlyOnScreen(id) {
            var focusedPid: pid_t = 0
            AXUIElementGetPid(win, &focusedPid)
            if let (retargetWin, retargetID) = retargetToActiveSpaceWindow(pid: focusedPid) {
                wlog("toggle: focused window id=\(id) off active space → retarget id=\(retargetID)")
                win = retargetWin
                id = retargetID
            } else {
                quietNotice("当前空间没有可折叠窗口",
                            log: "toggle: focused id=\(id) off active space; no on-space window")
                return
            }
        }
        wlog("toggle: app=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") id=\(id) alreadyShaded=\(shaded[id] != nil)")
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if isStickies(pid: pid) {
            performNativeStickiesShade(win)
            return
        }

        if shaded[id] != nil {
            unshade(id)
        } else {
            let options = focusRejoinEntries[id] != nil ? focusShadeOptions : nil
            shade(win, id, options: options)
        }
    }
    func performNativeStickiesShade(_ win: AXUIElement) {
        guard let pos = axPosition(win), let size = axSize(win) else {
            wlog("stickies: 取不到 pos/size，交还给原 app")
            return
        }
        let x = pos.x + min(max(size.width / 2, 24), max(24, size.width - 24))
        let y = pos.y + min(max(size.height * 0.08, 8), max(8, size.height / 2))
        let p = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<2 {
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        wlog("stickies: delegated native shade at (\(Int(p.x)),\(Int(p.y)))")
    }
    func makeShadePlan(win: AXUIElement, pos: CGPoint, size: CGSize,
                               pid: pid_t, profile: WindowChromeProfile,
                               options: ShadeInvocationOptions) -> ShadePlan? {
        guard windowIsVisible(pos: pos, size: size) else {
            wlog("plan: reject invisible/off-space window pid=\(pid)")
            return nil
        }
        if axBoolAttribute(win, "AXFullScreen") {
            wlog("plan: reject fullscreen window pid=\(pid)")
            return nil
        }
        if axBoolAttribute(win, kAXMinimizedAttribute as String) {
            wlog("plan: reject minimized window pid=\(pid)")
            return nil
        }
        let adobeProfile = profile.adobeProfile
        if adobeProfile.kind == .floatingPanel || !adobeProfile.canShade {
            wlog("plan: reject adobe panel pid=\(pid) kind=\(adobeProfile.kind.rawValue) reason=\(adobeProfile.reason)")
            return nil
        }

        let policy: ShadePolicy = profile.isQuickLook
            ? .closeQuickLookPreview
            : shadePolicy(for: pid)
        var mode = options.forcedAppearanceMode ?? appearanceMode
        var reason = options.forcedAppearanceMode == nil ? "user-mode" : "forced-\(mode.rawValue)"
        if profile.isQuickLook {
            reason += "-quicklook"
        }

        if options.forcedAppearanceMode == nil && mode == .nativeScreenshot && !hasScreenRecordingPermission() {
            mode = .proxyTitleBar
            reason = "screen-recording-missing"
        }
        if options.forcedAppearanceMode == nil && mode == .nativeScreenshot {
            if #unavailable(macOS 14.0) {
                mode = .proxyTitleBar
                reason = "screencapturekit-unavailable"
            }
        }
        if options.forcedAppearanceMode == nil,
           adobeProfile.kind != .none,
           mode == .proxyTitleBar,
           hasScreenRecordingPermission() {
            if #available(macOS 14.0, *) {
                mode = .nativeScreenshot
                reason = "adobe-\(adobeProfile.kind.rawValue)-native-chrome"
            }
        }
        return ShadePlan(mode: mode, policy: policy, reason: reason)
    }
    func resolvedSourceSpaceID(windowID id: CGWindowID,
                                       sourceDisplayID: CGDirectDisplayID?,
                                       profile: WindowChromeProfile) -> UInt64? {
        let mover = PrivateSLSWindowMover.shared
        if profile.isQuickLook,
           let sourceDisplayID,
           let activeSpaceID = mover.currentSpace(displayID: sourceDisplayID) {
            return activeSpaceID
        }
        return mover.windowSpace(id: id)
            ?? sourceDisplayID.flatMap { mover.currentSpace(displayID: $0) }
    }
    func shade(_ win: AXUIElement, _ id: CGWindowID,
                       options: ShadeInvocationOptions? = nil) {
        // 状态机防护：折叠中/已折叠/展开中的窗口再次触发折叠一律忽略，
        // 避免状态损坏（与 shadeOperationIDs 在途去重互为冗余）。
        let operationState = currentOperationState(id)
        guard !shadeOperationIDs.contains(id),
              operationState != .capturing,
              operationState != .folded,
              operationState != .restoring else {
            wlog("shade: ignore in-flight id=\(id) state=\(operationState.rawValue)")
            return
        }
        shadeOperationIDs.insert(id)
        transitionOperationState(id: id, to: .capturing, reason: "shade")
        var handedToAsyncCapture = false
        defer {
            if !handedToAsyncCapture {
                shadeOperationIDs.remove(id)
                // 未转入 async capture 就返回 = 本次折叠中止：capturing -> failed。
                if currentOperationState(id) == .capturing {
                    transitionOperationState(id: id, to: .failed, reason: "shade-abort")
                }
            }
        }
        guard let pos = axPosition(win), let size = axSize(win) else {
            quietNotice("无法读取窗口", log: "shade: 取不到 pos/size")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let role = axRole(win)
        // Adobe AE/Premiere 工作区窗口的 role 是 AXLayoutArea：有 layer-0 真实
        // CGWindow 背书时按窗口放行（见 isWindowLikeRole），其余非窗口角色照旧拒绝。
        let adobeLayoutWindow = role != kAXWindowRole as String
            && isWindowLikeRole(role, pid: pid) && cgWindowLayer(id) == 0
        guard role == kAXWindowRole as String || adobeLayoutWindow else {
            quietNotice("此窗口不能折叠", log: "shade: reject non-window role=\(role ?? "?") id=\(id)")
            return
        }
        let bundleID = appBundleID(pid: pid)
        let appName = appDisplayName(pid: pid)
        let title = axTitle(win)
        let autoJoinFocusShelf = shouldAutoJoinFocusShelf(id: id, pid: pid)
        let options = options ?? (autoJoinFocusShelf ? focusShadeOptions : defaultShadeOptions)
        if UserDefaults.standard.bool(forKey: shadeDebugWindowDumpDefaultsKey) {
            dumpWindow(win)
        }
        let profile = resolveWindowChromeProfile(win: win, id: id, pos: pos, size: size, pid: pid, title: title)
        guard let plan = makeShadePlan(win: win, pos: pos, size: size,
                                       pid: pid, profile: profile,
                                       options: options) else {
            quietNotice("此窗口不能折叠", log: "shade: plan rejected app=\(appName) id=\(id)")
            return
        }
        let policy = plan.policy
        let mode = plan.mode
        let quickLookReopenURL = profile.isQuickLook ? quickLookReopenURL(for: win) : nil
        if profile.isQuickLook, quickLookReopenURL == nil {
            wlog("quicklook: no direct reopen URL; will use Finder Space fallback title=\(title)")
        }
        let sourceDisplayID = displayID(for: screenForAXWindow(pos: pos, size: size))
        let sourceSpaceID = resolvedSourceSpaceID(windowID: id, sourceDisplayID: sourceDisplayID, profile: profile)
        let sourceSpaceMode = profile.isQuickLook ? "active-display" : "window"
        wlog(">>> shade id=\(id) app=\(appName) bundle=\(bundleID) mode=\(mode.rawValue) plan=\(plan.reason) policy=\(policy) sourceDisplay=\(sourceDisplayID.map { String($0) } ?? "-") sourceSpace=\(sourceSpaceID.map { String($0) } ?? "-") sourceSpaceMode=\(sourceSpaceMode) hasToolbar=\(profile.hasToolbar) adobe=\(profile.adobeProfile.kind.rawValue):\(profile.adobeProfile.reason) standardTitleBarOnly=\(profile.standardTitleBarOnly) toolbarlessStandard=\(profile.toolbarlessStandardTitleBar) preciseChrome=\(profile.preciseChrome) contentBelowTitleBar=\(profile.hasContentBelowTitleBar) axBarH=\(Int(profile.axBarHeight)) hitBarH=\(Int(profile.hitBarHeight))")

        func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {
            shadeOperationIDs.remove(id)
            transitionOperationState(id: id, to: .folded, reason: "install")
            configureShadedAccessibility(for: overlay, id: id, appName: appName, title: title)
            // 折叠事务序：先把焦点交给当前 Space 的继承人，再隐藏真实窗口。
            // 隐藏非前台窗口不会触发 macOS 的焦点级联（跳 Space / 激活兄弟窗口的病灶）。
            // 无处交接（当前 Space 只有这一个窗口）时 app-hide 不安全，改走 minimize。
            let appHideSafe = handOffFocusBeforeHiding(win: win, pid: pid, id: id)
            // crash consistency：先把 durable recovery intent 落盘，再执行任何
            // 可能让窗口长期不可见的动作。若进程在 hideWindow 中途被杀，重启后
            // rescue 仍能按 intent 找回窗口；隐藏成功验证后由 recordShadeJournal
            // 把同一条 entry 更新为 folded（或按最终隐藏方式清掉）。
            recordShadeRecoveryIntent(id: id, pid: pid, bundleID: bundleID,
                                      appName: appName, title: title,
                                      originalPosition: pos, originalSize: size,
                                      sourceDisplayID: sourceDisplayID,
                                      sourceSpaceID: sourceSpaceID)
            let hide = hideWindow(win, pid: pid, originalPosition: pos, size: size,
                                  policy: policy, appHideSafe: appHideSafe)
            // minimize / app-hide 的状态读回是异步的（最小化动画进行中 kAXMinimized
            // 尚未翻转、NSRunningApplication.isHidden 缓存滞后），立即验证会产生假阴性。
            // 立即通过 → 立即 reveal；否则延迟验证（+0.15/+0.45s），通过后才 reveal，
            // 两次仍失败才补救/回滚。见 scheduleFoldVerification。
            let hideVerifiedNow = hideTookEffect(hide, win: win, pid: pid, id: id, size: size)
            recordShadeJournal(id: id, win: win, hide: hide, pid: pid, bundleID: bundleID,
                               appName: appName, title: title,
                               originalPosition: pos, originalSize: size,
                               mode: mode, policy: policy, planReason: plan.reason,
                               stage: .folded,
                               sourceDisplayID: sourceDisplayID,
                               sourceSpaceID: sourceSpaceID)
            prepareOverlayWindowForSpaceAssignment(overlay)
            let oid = cgWindowID(for: overlay)
            if let oid {
                overlayIDs.insert(oid)
                if let sourceSpaceID {
                    if PrivateSLSWindowMover.shared.moveWindow(id: oid, toSpace: sourceSpaceID) {
                        wlog("space: overlay assigned id=\(oid) source=\(id) sid=\(sourceSpaceID)")
                    } else if PrivateSLSWindowMover.shared.reassociateWindowByGeometry(id: oid) {
                        wlog("space: overlay reassociated by geometry id=\(oid) source=\(id)")
                    } else {
                        wlog("space: overlay assignment unavailable id=\(oid) source=\(id)")
                    }
                } else if PrivateSLSWindowMover.shared.reassociateWindowByGeometry(id: oid) {
                    wlog("space: overlay reassociated by geometry id=\(oid) source=\(id) sid=-")
                }
            }
            let observer = (hide == .quickLookClosed || hide == .ownWindowOrderedOut)
                ? nil
                : makeRevealObserver(pid: pid, win: win, id: id)
            let state = ShadeState(element: win, sourceWindowID: id,
                                   originalPosition: pos, originalSize: size,
                                   sourceDisplayID: sourceDisplayID,
                                   sourceSpaceID: sourceSpaceID,
                                   overlay: overlay,
                                   overlayID: oid, hide: hide, pid: pid, bundleID: bundleID,
                                   appName: appName, title: title, appearanceMode: mode,
                                   lifecycleStage: .folded,
                                   previewImage: previewImage,
                                   quickLookReopenURL: quickLookReopenURL,
                                   ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                   observer: observer)
            shaded[id] = state
            scheduleSourceSpaceReturnIfNeeded(id: id, state: state)
            if hideVerifiedNow {
                if enforceOverlaySpaceInvariant(id: id, state: state, reason: "install") {
                    revealPreparedOverlay(overlay)
                }
            } else {
                wlog("shade: hide not yet verified; deferring overlay reveal id=\(id) hide=\(hide)")
                scheduleFoldVerification(id: id, attempt: 1)
            }
            hoverPreviewSuppressedUntil[id] = Date().addingTimeInterval(0.7)
            rejoinFocusStackAfterShadeIfNeeded(id: id, overlay: overlay)
            if autoJoinFocusShelf {
                joinFocusShelfAfterShadeIfNeeded(id: id, overlay: overlay)
            }
            if options.rebuildMenuAfterInstall {
                rebuildMenu()
            }
            if options.emitFoldFeedback {
                playFoldSound()
            }
        }

        func installInteractiveNativeCollapse(barH: CGFloat) -> Bool {
            let targetH = min(max(barH, titleBarHeight), min(size.height, 300))
            let target = CGSize(width: size.width, height: targetH)
            let err = setAXSize(win, target)
            guard err == .success else {
                wlog("    interactive native rejected size err=\(err) targetH=\(Int(targetH))")
                return false
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            guard let actual = axSize(win) else {
                setAXSize(win, size)
                setAXPosition(win, pos)
                wlog("    interactive native cannot read actual size after resize")
                return false
            }

            let maxAcceptedH = min(size.height, max(targetH + 16, CGFloat(72)))
            guard actual.height <= maxAcceptedH else {
                setAXSize(win, size)
                setAXPosition(win, pos)
                wlog("    interactive native fallback actualH=\(Int(actual.height)) targetH=\(Int(targetH)) maxAcceptedH=\(Int(maxAcceptedH))")
                return false
            }

            setAXPosition(win, pos)
            let observer = makeRevealObserver(pid: pid, win: win, id: id)
            clearShadeJournal(id: id)
            shaded[id] = ShadeState(element: win, sourceWindowID: id,
                                    originalPosition: pos, originalSize: size,
                                    sourceDisplayID: sourceDisplayID,
                                    sourceSpaceID: sourceSpaceID,
                                    overlay: nil,
                                    overlayID: nil, hide: .none, pid: pid, bundleID: bundleID,
                                    appName: appName, title: title, appearanceMode: mode,
                                    lifecycleStage: .folded,
                                    previewImage: nil,
                                    quickLookReopenURL: nil,
                                    ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                    observer: observer)
            wlog("    interactive native finalBarH=\(Int(targetH)) actualH=\(Int(actual.height))")
            transitionOperationState(id: id, to: .folded, reason: "interactive-native")
            if options.rebuildMenuAfterInstall {
                rebuildMenu()
            }
            if options.emitFoldFeedback {
                playFoldSound()
            }
            return true
        }

        if mode == .interactiveNative {
            let minimumBarH = profile.standardCropHeight
            let fixedBarH = fixedNonstandardChromeHeight(pid: pid)
            let fallbackBarH = fixedBarH ?? fallbackControlPaddedChromeHeight(pid: pid, minimum: minimumBarH) ?? profile.axBarHeight
            let barH = profile.standardTitleBarOnly
                ? profile.standardCropHeight
                : min(fixedBarH ?? max(profile.axBarHeight, fallbackBarH), min(size.height, 300))
            if installInteractiveNativeCollapse(barH: barH) { return }
            wlog("    interactive native unavailable → fallback screenshot")
        }

        if mode == .classicSemantic {
            let barH = min(classicTitleBarHeight, min(size.height, 300))
            let overlay = makeClassicOverlay(axPos: pos, width: size.width, height: barH,
                                             pid: pid, appName: appName, title: title, id: id)
            wlog("    classic finalBarH=\(Int(barH)) appTitle=\"\(appName)\" windowTitle=\"\(title)\"")
            installOverlay(overlay, mode: mode, previewImage: nil)
            return
        }

        if mode == .proxyTitleBar {
            let barH = min(proxyTitleBarHeight, min(size.height, 300))
            let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
            let windowManagementCapability = realWindowManagementCapability(win)
            guard #available(macOS 14.0, *) else {
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=-")
                installOverlay(overlay, mode: mode, previewImage: nil)
                return
            }
            let quickPreview = quickWindowPreviewImage(id: id, logicalSize: size)
            if quickPreview != nil || !options.capturePreview {
                // legacy 快照已经成功，或者这次折叠本来就不需要预览（比如专注 shelf
                // 批量折叠）——两种情况都跟以前一样同步立刻装上，不引入任何延迟。
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy immediate finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(quickPreview == nil ? "-" : "quick") capture=\(options.capturePreview)")
                installOverlay(overlay, mode: mode, previewImage: quickPreview)
                return
            }
            // legacy 快照失败，且这次折叠需要预览：在真实窗口被隐藏前先补一次有超时
            // 的 ScreenCaptureKit 截图，而不是像以前那样先装后台再异步补——隐藏之后
            // 窗口就不在可截图列表里了，补拍几乎必然也失败，这条折叠条就永久没有
            // 预览了（menu 悬停/标题栏 peek 的懒截图重试会撞上同一堵墙）。宁可在这
            // 个本来就少见的失败分支上多花一点点时间，也不要用「先装后补」制造一堵
            // 永远撞不过去的墙。
            handedToAsyncCapture = true
            Task { @MainActor in
                defer {
                    self.shadeOperationIDs.remove(id)
                    if self.currentOperationState(id) == .capturing {
                        self.transitionOperationState(id: id, to: .failed, reason: "shade-capture-abort")
                    }
                }
                let capturedImage = await self.captureWindowWithTimeout(id: id, axPos: pos, size: size,
                                                                         maxPixelSize: hoverPreviewMaxPixelSize,
                                                                         timeoutNanoseconds: shadeCaptureTimeoutNanoseconds)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy pre-hide-capture finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(capturedImage == nil ? "-" : "sck")")
                installOverlay(overlay, mode: mode,
                               previewImage: capturedImage.map { NSImage(cgImage: $0, size: size) })
            }
            return
        }

        guard #available(macOS 14.0, *) else {
            quietNotice("系统版本不支持", log: "shade: ScreenCaptureKit unavailable on this macOS")
            return
        }
        handedToAsyncCapture = true
        Task { @MainActor in
            defer {
                self.shadeOperationIDs.remove(id)
                if self.currentOperationState(id) == .capturing {
                    self.transitionOperationState(id: id, to: .failed, reason: "shade-capture-abort")
                }
            }
            // 折叠一个正被置顶捕获的窗口：系统会在其交通灯处叠加录屏标识，
            // 截图前先停掉置顶流并等标识消失，让卷帘条的红绿灯落在干净背景上。
            if self.pinnedPreviewController.stopPreviewBeforeFoldCapture(id: id) {
                wlog("    pinned stream stopped before fold capture; waiting for indicator to clear")
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let shouldParkFocus = !profile.isQuickLook
            if shouldParkFocus {
                parkFocusForInactiveCapture()
                try? await Task.sleep(nanoseconds: 35_000_000)       // 等 WindowServer 把整条 toolbar 重绘成非活跃态
            }
            guard let full = await captureWindowWithTimeout(id: id,
                                                            axPos: pos,
                                                            size: size,
                                                            timeoutNanoseconds: shadeCaptureTimeoutNanoseconds) else {
                if shouldParkFocus {
                    releaseFocusParking(reactivate: nil)
                }
                let barH = min(proxyTitleBarHeight, min(size.height, 300))
                let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
                let windowManagementCapability = realWindowManagementCapability(win)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("shade: screenshot timeout/fail → proxy fallback id=\(id) app=\(appName)")
                installOverlay(overlay, mode: .proxyTitleBar, previewImage: nil)
                return
            }
            if shouldParkFocus {
                releaseFocusParking(reactivate: nil)
            }
            // 裁出顶部标题栏条：chrome 高度判定、健康检查、圆角镜像都是纯 CPU
            // 像素计算（4K Retina 全宽可达数 MB），挪到后台队列执行，避免在
            // MainActor 上分配大缓冲并逐像素扫描。AX 命中区和 AppKit 覆盖层
            // 仍留在主线程。
            let preparation = await withCheckedContinuation {
                (continuation: CheckedContinuation<NativeStripPreparation, Never>) in
                pixelAnalysisQueue.async { [full, size, profile, pid] in
                    continuation.resume(returning: prepareNativeStrip(full: full, logicalSize: size,
                                                                      profile: profile, pid: pid))
                }
            }
            let barH = preparation.barH
            let buttonRects = trafficLightRects(
                trafficLightRects(win, winTopLeft: pos, barH: barH),
                normalizedFor: profile.trafficLights
            )  // 最终高度确定后再换算命中区
            let windowManagementCapability = realWindowManagementCapability(win)
            wlog("    capture full=\(full.width)x\(full.height) scale=\(preparation.scale) fixedBarH=\(preparation.fixedBarH.map { String(format: "%.1f", $0) } ?? "-") visualBarH=\(preparation.visualBarH.map { String(Int($0)) } ?? "-") fallbackBarH=\(Int(preparation.fallbackBarH)) standardBarH=\(String(format: "%.1f", preparation.standardBarH)) finalBarH=\(String(format: "%.1f", barH)) buttons=\(buttonRects.count) windowManagement=\(windowManagementCapability) cropPxH=\(max(1, Int(ceil(barH * preparation.scale)))) boundary=\(preparation.boundary)")
            guard let strip = preparation.strip else {
                activateApp(pid: pid)
                quietNotice("折叠失败", log: "shade: 裁剪失败")
                return
            }
            if preparation.brokenHealth.0 {
                let proxyBarH = min(proxyTitleBarHeight, min(size.height, 300))
                let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: proxyBarH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                let preview = NSImage(cgImage: full, size: size)
                wlog("    native strip invalid → proxy fallback id=\(id) app=\(appName) reason=\(preparation.brokenHealth.1)")
                installOverlay(overlay, mode: .proxyTitleBar, previewImage: preview)
                return
            }

            let overlay = makeScreenshotOverlay(image: strip, axPos: pos, width: size.width, height: barH,
                                                buttons: buttonRects, id: id,
                                                windowManagement: windowManagementCapability,
                                                trafficLights: profile.trafficLights)
            let preview = NSImage(cgImage: full, size: size)
            installOverlay(overlay, mode: mode, previewImage: preview)
        }
    }
    func captureWindow(id: CGWindowID, axPos: CGPoint, size: CGSize,
                               maxPixelSize: CGSize? = nil) async -> CGImage? {
        guard let content = await ShareableContentCache.shared.content(requiring: id),
              let scWindow = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = backingScaleForAXWindow(pos: axPos, size: size)
        var pixelWidth = max(1, Int(ceil(size.width * scale)))
        var pixelHeight = max(1, Int(ceil(size.height * scale)))
        if let maxPixelSize {
            let outputScale = min(maxPixelSize.width / CGFloat(pixelWidth),
                                  maxPixelSize.height / CGFloat(pixelHeight),
                                  1)
            pixelWidth = max(1, Int(ceil(CGFloat(pixelWidth) * outputScale)))
            pixelHeight = max(1, Int(ceil(CGFloat(pixelHeight) * outputScale)))
        }
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,
                                          maxPixelSize: CGSize? = nil,
                                          timeoutNanoseconds: UInt64) async -> CGImage? {
        // 折叠路径的 500ms 短 TTL 截图缓存：快速连续折叠同一窗口时复用，
        // 避免重复 ScreenCaptureKit capture。悬停预览的懒截图不走这里。
        // key 区分 capture variant 与请求像素档位，预览小图与完整 Retina
        // 截图不会互相串用。
        let variant: WindowSnapshotVariant = maxPixelSize == nil ? .nativeChrome : .preview
        let key = WindowSnapshotKey(windowID: id, variant: variant, maxPixelSize: maxPixelSize)
        if let cached = WindowSnapshotCache.shared.cachedImage(key: key) {
            return cached
        }

        // 同一窗口、同一 variant 的重复请求 join 已在途的 capture，不再堆积
        // 新的重复截图任务；超时由共享任务内部管理（所有调用方用同一个
        // shadeCaptureTimeoutNanoseconds）。
        if let existing = WindowSnapshotCache.shared.inFlightTask(for: key) {
            return await existing.value
        }

        // 槽先建、任务后建：任务完成时按槽身份清理在途注册表，不会误删
        // 后到的同 key 任务。任务弱持有槽：若发布失败（已有同 key 在途），
        // 槽未被缓存持有，任务结束时清理自动 no-op。
        let slot = WindowSnapshotInFlightSlot(key: key)
        let task: Task<CGImage?, Never> = Task { [weak self, weak slot] in
            defer {
                slot?.markCompleted()
            }
            guard let self else { return nil }
            return await self.raceCaptureWithTimeout(id: id, axPos: axPos, size: size,
                                                     maxPixelSize: maxPixelSize,
                                                     timeoutNanoseconds: timeoutNanoseconds,
                                                     key: key)
        }
        slot.task = task
        if !WindowSnapshotCache.shared.registerInFlight(slot: slot) {
            // 创建任务期间已有同 key 任务被发布：改用对方的。
            if let existing = WindowSnapshotCache.shared.inFlightTask(for: key) {
                return await existing.value
            }
            return await task.value
        }
        let image = await task.value
        // 任务已完成的槽在等待结束后按身份清理（幂等，误删不了后到的同 key 任务）。
        WindowSnapshotCache.shared.completeInFlight(slot)
        return image
    }

    // 单次 capture 的内部竞速：timeout 获胜 → 取消 capture task；capture 完成 →
    // 取消 timeout task。被取消或过期的 capture 不写回缓存。continuation 仍然
    // 只允许 resume 一次（SingleResumeGuard），两个赛跑的 Task 不会双 resume。
    private func raceCaptureWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,
                                        maxPixelSize: CGSize?, timeoutNanoseconds: UInt64,
                                        key: WindowSnapshotKey) async -> CGImage? {
        let resumeGuard = SingleResumeGuard()
        let image: CGImage? = await withCheckedContinuation { continuation in
            let captureTask: Task<CGImage?, Never> = Task { [weak self] in
                guard let self else { return nil }
                let image = await self.captureWindow(id: id, axPos: axPos, size: size,
                                                     maxPixelSize: maxPixelSize)
                // 被取消/超时过期的 capture 不写回缓存，避免晚到的结果污染 TTL 窗口。
                guard !Task.isCancelled else { return nil }
                if let image {
                    WindowSnapshotCache.shared.store(image: image, key: key)
                }
                return image
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if await resumeGuard.tryResume() {
                    captureTask.cancel()
                    continuation.resume(returning: nil)
                }
            }
            Task {
                let image = await captureTask.value
                timeoutTask.cancel()
                if await resumeGuard.tryResume() {
                    continuation.resume(returning: image)
                }
            }
        }
        return image
    }
}
