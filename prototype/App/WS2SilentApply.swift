// WindowShade 2.1 · 静音命令的宿主。只调用已经存在的启动台、窗口排布和番茄钟。
// 窗口必须是确认时冻结的那一扇；对不上就不改当前焦点。
import Cocoa

@MainActor
enum WS2SilentApply {
    struct WindowTarget {
        var id: CGWindowID
        var element: AXUIElement
        var revision: UInt64
        var pid: pid_t = 0
    }

    private static func launchpadSeen(
        _ launchpad: LaunchpadController,
        on screen: NSScreen,
        commandID: String
    ) -> SilentExecutionResult {
        let onFrozen = launchpad.panelIsOn(screen)
        return WS2SilentEffectJudge.launchpad(
            panelVisible: launchpad.isShowing && onFrozen,
            onFrozenScreen: onFrozen,
            commandID: commandID)
    }

    private static func completed(_ command: String, _ target: String) -> SilentExecutionResult {
        .completed(WS2EffectReceipt(commandID: command, targetID: target, observed: true))
    }

    private static func notDone() -> SilentExecutionResult {
        .failed("这一笔没有做成")
    }

    @discardableResult
    static func perform(
        _ request: WS2SilentHostRequest,
        launchpad: LaunchpadController,
        runtime: WS2AppRuntime,
        gestures: TrackpadGestureController,
        screen: NSScreen?,
        window: WindowTarget? = nil,
        draft: inout WS2SilentDraftHost,
        boundSessionID: String? = nil,
        activities: WS2SilentActivityBoard = WS2SilentActivityBoard(),
        assistant: inout WS2SilentAssistant,
        cover: inout WS2SilentCover.State,
        allowedModels: Set<String> = [],
        allowedEfforts: Set<String> = []
    ) -> SilentExecutionResult {
        switch request {
        case .showLaunchpad(let destination):
            let presentation = WS2SilentProductPort.launchPresentation(destination)
            if presentation.dismissesIfAlreadyOpen {
                launchpad.hide(reason: "silent")
                return launchpad.isShowing ? .unknown(0) : completed("launcher.dismiss", "")
            }
            guard presentation.screen == .caller, let screen else { return .unavailable("没屏幕") }
            switch destination {
            case .nextPage:
                launchpad.turnPage(by: 1, on: screen)
                return launchpadSeen(launchpad, on: screen, commandID: "launcher.nextPage")
            case .previousPage:
                launchpad.turnPage(by: -1, on: screen)
                return launchpadSeen(launchpad, on: screen, commandID: "launcher.previousPage")
            case .home, .today, .library, .spotlight, .back, .dismiss:
                guard let mapped = launchDestination(destination) else { return notDone() }
                launchpad.present(mapped, on: screen)
                return launchpadSeen(launchpad, on: screen, commandID: destination.rawValue)
            }
        case .placeWindow(let id, let revision, let placement):
            guard let screen, let window,
                  WS2SilentProductPort.acceptsFrozenWindow(
                    requestedID: id,
                    requestedRevision: revision,
                    liveID: String(window.id),
                    liveRevision: window.revision),
                  let action = GestureAction(rawValue: placement.rawValue),
                  action != .shade, action != .expand, action != .undoPlacement else { return notDone() }
            guard window.pid != 0, focusedPID(window.element) == window.pid else { return notDone() }
            switch WS2SilentProductPort.windowRoute(placement) {
            case .tileVisibleFrame, .centerKeepingSize:
                _ = gestures.placeFromLaunchpad(window.element, id: window.id, action: action, screen: screen)
                let matched = gestures.observedFrameMatches(window.element, action: action, screen: screen)
                return WS2SilentEffectJudge.placement(frameMatched: matched, commandID: placement.rawValue, targetID: id)
            }
        case .showFocusStatus:
            runtime.showFocusStatus()
            return runtime.showsFocusCard ? .displayed("只看不计时") : .unavailable("没打开")
        case .startFocus:
            let idle = runtime.focus.model.phase == .idle
            runtime.startFocus()
            return WS2SilentEffectJudge.focusStart(wasIdle: idle, runningAfter: runtime.focus.model.phase != .idle)
        case .pauseFocus:
            runtime.pauseFocus()
            return runtime.focus.model.isPaused ? completed("focus.pause", "") : notDone()
        case .resumeFocus:
            let paused = runtime.focus.model.isPaused
            runtime.resumeFocus()
            if paused && !runtime.focus.model.isPaused {
                return completed("focus.resume", "")
            }
            return notDone()
        case .glance(let id, let revision):
            guard let window, frozen(id, revision, window) else { return .unavailable("没预览") }
            let invoked = gestures.owner.glance.showHeld(window.id)
            // 面板外框不够：要等到首帧真的挂上视频层（isLive）才算观察到预览。
            let live = gestures.owner.glance.isLive(window.id)
            return WS2SilentEffectJudge.glance(windowID: UInt64(window.id), invoked: invoked, visible: live)
        case .openLaunchpadFolder(let id):
            guard let screen, !id.isEmpty else { return .unavailable("还没选") }
            guard launchpad.openFolder(id, on: screen) else { return notDone() }
            return launchpadSeen(launchpad, on: screen, commandID: "launcher.openFolder")
        case .adoptDraft(let id, let revision):
            let adopted = draft.adopt(id: id, revision: revision) == .preview && draft.mark != .sent
            return adopted ? .displayed("已采用草稿") : notDone()
        case .submitDraft(let id, let revision):
            let result = draft.submit(commandID: "assistant.sendDraft", id: id, revision: revision, boundSessionID: boundSessionID)
            return WS2SilentDraftReceipt.execution(result)
        case .undoWindow(let id, let revision):
            guard let window, frozen(id, revision, window) else { return notDone() }
            _ = gestures.undoOwnedPlacement(window.element, id: window.id)
            return .unknown(0)
        case .moveToCallerDisplay(let id, let revision):
            guard let screen, let window,
                  WS2SilentProductPort.canMoveToCallerDisplay(
                    callerScreenProvided: true,
                    windowMatches: frozen(id, revision, window)) else { return notDone() }
            _ = gestures.moveToCallerScreen(window.element, id: window.id, screen: screen)
            return gestures.windowIsOn(window.element, screen: screen)
                ? completed("window.moveToSelectedDisplay", id)
                : .unknown(0)
        case .showUsage, .refreshUsage, .showAccountChooser:
            return WS2SilentEffectJudge.usageRefresh(protocolParsed: false)
        case .showAssistantRead:
            guard !assistant.turnStarted, !assistant.sessionStarted else { return notDone() }
            runtime.openOwned()
            return .displayed("编程会话")
        case .showActivity:
            let before = activities.present
            guard activities.present == before, !activities.startsPlayback else { return notDone() }
            return .displayed(activities.present.isEmpty ? "没有" : "有活动")
        case .showNativeStop(let id, let revision):
            let mark = assistant.showNativeStop(turnID: id, revision: revision)
            guard mark == .showingNativeStop, assistant.stopMark != .stopped, !assistant.turnStarted else { return notDone() }
            return .displayed("已显示停止")
        case .setNextModel(let id, _):
            guard assistant.setNextModel(id, allowed: allowedModels), !assistant.turnStarted else { return notDone() }
            return .displayed("已记下模型")
        case .setNextEffort(let id, _):
            guard assistant.setNextEffort(id, allowed: allowedEfforts), !assistant.turnStarted else { return notDone() }
            return .displayed("已记下档位")
        case .steerDraft(let id, let revision):
            let mark = assistant.steer(id: id, revision: revision, boundSessionID: boundSessionID)
            guard mark == .waitingForAck, assistant.steerMark != .acknowledged, !assistant.turnStarted else { return notDone() }
            return .waiting(1)
        case .collapseWindow(let id, let revision):
            guard let window, frozen(id, revision, window) else { return notDone() }
            if gestures.owner.shaded[window.id] != nil {
                return .alreadySatisfied("已收起")
            }
            let foldID = window.id
            _ = gestures.owner.registerFoldWaiter(id: foldID) { success in
                MainActor.assumeIsolated {
                    gestures.owner.noteSilentFoldCompletion(id: foldID, ok: success)
                }
            }
            gestures.owner.shade(window.element, window.id)
            return .waiting(1)
        case .expandWindow(let id, let revision):
            guard let window, frozen(id, revision, window) else { return notDone() }
            guard gestures.owner.shaded[window.id] != nil else {
                return .alreadySatisfied("已展开")
            }
            _ = gestures.owner.unshade(window.id)
            // 字典移除不等于原窗已可见；宿主短轮询终态（R03）。
            return .waiting(1)
        case .unlockNoted:
            return .unavailable("不解锁")
        case .fillRefused:
            return .unavailable("不代填")
        case .deviceRead:
            return .displayed("未知")
        case .carPlayUnavailable:
            return .unavailable("还不能接收")
        case .challengeOnly(let id):
            guard let command = WS2SilentCatalog.lookup(id),
                  let outcome = WS2SilentChallenge.outcome(for: command),
                  !outcome.unlocks, !outcome.fillsPassword else { return notDone() }
            return .unavailable("要用原来的确认")
        case .showNamed(let id):
            switch WS2SilentSurface.surface(for: id) {
            case .settings(let page):
                gestures.owner.showSettingsWindow(section: section(page))
                return .displayed(WS2SilentReadout.sentence(id))
            case .windowBrowser:
                gestures.owner.openWindowBrowserPanel()
                return .displayed("已开窗口浏览")
            case .readout:
                if id == "input.pause" {
                    gestures.owner.inputController.pauseHooks()
                    return gestures.owner.inputController.hooksPaused ? .displayed("输入已暂停") : notDone()
                }
                if id == "privacy.cover" || id == "scene.conversation" {
                    let obs = gestures.owner.silentPrivacyCover.coverAllScreens()
                    if obs.overlayCreated, obs.allScreensCovered {
                        cover.scopeSelected = true
                        _ = WS2SilentCover.cover(&cover, overlayCreated: true)
                    }
                    return WS2SilentEffectJudge.cover(
                        overlayCreated: obs.overlayCreated,
                        commandID: id,
                        allScreensCovered: obs.allScreensCovered,
                        missingScreens: obs.missingScreens)
                }
                if WS2SilentDraftCommand.handles(id) {
                    let applied = WS2SilentDraftCommand.apply(id, targetID: "", revision: 0, to: &draft)
                    return applied ? .displayed(WS2SilentReadout.sentence(id, draft: draft)) : notDone()
                }
            }
            return .displayed(WS2SilentReadout.sentence(id))
        case .intent(let id, let revision, let name):
            if WS2SilentDraftCommand.handles(name) {
                let applied = WS2SilentDraftCommand.apply(name, targetID: id, revision: revision, to: &draft)
                return applied ? .displayed(WS2SilentReadout.sentence(name, draft: draft)) : notDone()
            }
            if let effect = WS2SilentWindowEffect.effect(for: name) {
                guard !effect.unlocks, !effect.entersSystemFullscreen else { return notDone() }
                guard let window, frozen(id, revision, window) else { return notDone() }
                return perform(effect, window: window, gestures: gestures, screen: screen)
            }
            _ = WS2SilentSim.record(name: name, target: id, revision: revision)
            return notDone()
        case .waiting, .refused:
            return notDone()
        }
    }

    private static func frozen(_ id: String, _ revision: UInt64, _ window: WindowTarget) -> Bool {
        WS2SilentProductPort.acceptsFrozenWindow(
            requestedID: id,
            requestedRevision: revision,
            liveID: String(window.id),
            liveRevision: window.revision)
    }

    private static func focusedPID(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private static func perform(
        _ effect: WS2SilentWindowEffect,
        window: WindowTarget,
        gestures: TrackpadGestureController,
        screen: NSScreen?
    ) -> SilentExecutionResult {
        let owner = gestures.owner
        let focused = focusedWindow().flatMap { windowID(of: $0) }
        let same = focused == window.id
        switch effect {
        case .tuck:
            guard same else { return notDone() }
            _ = owner.notch.tuckFocused()
            return owner.notch.isTucked(window.id) ? completed("window.tuck", String(window.id)) : .unknown(0)
        case .untuck:
            guard owner.notch.isTucked(window.id) else { return notDone() }
            owner.notch.release(window.id, reason: "silent")
            return owner.notch.isTucked(window.id) ? .unknown(0) : completed("window.untuck", String(window.id))
        case .magicTile:
            guard same else { return notDone() }
            _ = gestures.magicTile(main: window.id, element: window.element, announce: false)
            return .unknown(0)
        case .unpin:
            guard same, WS2SilentEngineGate.calls("window.unpin") else { return notDone() }
            let preview = owner.pinnedPreviewController
            guard preview.isPreviewing(id: window.id) else { return notDone() }
            preview.stopPreviewFromMenu(id: window.id)
            return preview.isPreviewing(id: window.id) ? .unknown(0) : completed("window.unpin", String(window.id))
        case .place, .collapse, .expand, .undo, .move, .glance:
            return .unknown(0)
        case .pin:
            guard same else { return notDone() }
            let already = owner.pinnedPreviewController.isPreviewing(id: window.id)
            if !already {
                let pinID = window.id
                owner.pinnedPreviewController.startPreview(
                    targetWindowID: window.id, pid: window.pid, axWindow: window.element
                ) { result in
                    // R03：不得丢掉异步完成；成败记入置顶控制器供宿主/探针读取。
                    MainActor.assumeIsolated {
                        owner.pinnedPreviewController.noteSilentCompletion(id: pinID, result: result)
                    }
                }
            }
            return WS2SilentEffectJudge.pin(alreadyPreviewing: already, started: !already)
        case .slideOver:
            guard let screen else { return .unavailable("没屏幕") }
            let already = owner.slideOver.isSlideOver(window.id)
            if !already {
                owner.slideOver.enter(window.element, id: window.id, pid: window.pid, on: screen)
            }
            return WS2SilentEffectJudge.asyncWindow(
                already: already,
                started: owner.slideOver.isSlideOver(window.id),
                satisfied: "已在侧拉")
        case .leaveSlideOver:
            guard owner.slideOver.isSlideOver(window.id) else {
                return .alreadySatisfied("没在侧拉")
            }
            owner.slideOver.exit(reason: "silent")
            return .waiting(1)
        case .pictureInPicture:
            guard let screen else { return .unavailable("没屏幕") }
            let already = owner.pip.isInPictureInPicture(window.id)
            if !already {
                owner.pip.enter(window.element, id: window.id, pid: window.pid, on: screen)
            }
            return WS2SilentEffectJudge.asyncWindow(
                already: already,
                started: owner.pip.isInPictureInPicture(window.id),
                satisfied: "已在画中画")
        case .leavePictureInPicture:
            guard owner.pip.isInPictureInPicture(window.id) else {
                return .alreadySatisfied("没在画中画")
            }
            owner.pip.exit(window.id, activate: false)
            return .waiting(1)
        case .choose, .chooseDisplay, .batchReview, .strip, .stripOverview, .scene:
            _ = WS2SilentSim.record(name: "\(effect)", target: String(window.id), revision: window.revision)
            return notDone()
        }
    }

    private static func section(_ page: WS2SilentSettingsPage) -> WindowShadeSettingsSection {
        switch page {
        case .appearance: return .effects
        case .windows: return .browser
        case .shortcuts: return .shortcuts
        case .permissions, .privacy: return .permissions
        case .silent, .general: return .shade
        }
    }

    private static func launchDestination(_ destination: WS2SilentLaunchDestination) -> LaunchpadController.Destination? {
        switch destination {
        case .home: return .home
        case .today: return .today
        case .library: return .library
        case .spotlight: return .spotlight
        case .back: return .back
        case .dismiss, .nextPage, .previousPage: return nil
        }
    }
}
