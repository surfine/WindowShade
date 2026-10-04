// WindowShade 2.1 · 静音命令的宿主。只调用已经存在的启动台、窗口排布和番茄钟。
// 窗口必须是确认时冻结的那一扇；对不上就不改当前焦点。
import Cocoa

@MainActor
enum WS2SilentApply {
    struct WindowTarget {
        var id: CGWindowID
        var element: AXUIElement
        var revision: UInt64
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
    ) -> Bool {
        switch request {
        case .showLaunchpad(let destination):
            let presentation = WS2SilentProductPort.launchPresentation(destination)
            if presentation.dismissesIfAlreadyOpen {
                launchpad.hide(reason: "silent")
                return true
            }
            guard presentation.screen == .caller, let screen else { return false }
            switch destination {
            case .nextPage:
                launchpad.turnPage(by: 1, on: screen)
                return launchpad.isShowing
            case .previousPage:
                launchpad.turnPage(by: -1, on: screen)
                return launchpad.isShowing
            case .home, .today, .library, .spotlight, .back, .dismiss:
                guard let mapped = launchDestination(destination) else { return false }
                launchpad.present(mapped, on: screen)
                return destination == .spotlight || destination == .back || launchpad.isShowing
            }
        case .placeWindow(let id, let revision, let placement):
            guard let screen, let window,
                  WS2SilentProductPort.acceptsFrozenWindow(
                    requestedID: id,
                    requestedRevision: revision,
                    liveID: String(window.id),
                    liveRevision: window.revision),
                  let action = GestureAction(rawValue: placement.rawValue),
                  action != .shade, action != .expand, action != .undoPlacement else { return false }
            switch WS2SilentProductPort.windowRoute(placement) {
            case .tileVisibleFrame, .centerKeepingSize:
                return gestures.placeFromLaunchpad(window.element, id: window.id, action: action, screen: screen)
            }
        case .showFocusStatus:
            runtime.showFocusStatus()
            return true
        case .startFocus:
            runtime.startFocus()
            return true
        case .pauseFocus:
            runtime.pauseFocus()
            return true
        case .resumeFocus:
            runtime.resumeFocus()
            return true
        case .glance(let id, let revision):
            // 看一眼不打开窗口、不抢走焦点。策略成立才算做完。
            return !WS2SilentProductPort.glanceActivatesWindow(id: id, revision: revision)
        case .openLaunchpadFolder(let id):
            guard let screen, !id.isEmpty else { return false }
            return launchpad.openFolder(id, on: screen)
        case .adoptDraft(let id, let revision):
            return draft.adopt(id: id, revision: revision) == .preview && draft.mark != .sent
        case .submitDraft(let id, let revision):
            let result = draft.submit(commandID: "assistant.sendDraft", id: id, revision: revision, boundSessionID: boundSessionID)
            switch result {
            case .keptLocal, .waitingForAck:
                return draft.mark != .sent
            case .preview, .sent, .refused:
                return false
            }
        case .undoWindow(let id, let revision):
            guard let window,
                  WS2SilentProductPort.acceptsFrozenWindow(
                    requestedID: id,
                    requestedRevision: revision,
                    liveID: String(window.id),
                    liveRevision: window.revision) else { return false }
            return gestures.undoOwnedPlacement(window.element, id: window.id)
        case .moveToCallerDisplay(let id, let revision):
            guard let screen, let window,
                  WS2SilentProductPort.canMoveToCallerDisplay(
                    callerScreenProvided: true,
                    windowMatches: WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: id,
                        requestedRevision: revision,
                        liveID: String(window.id),
                        liveRevision: window.revision)) else { return false }
            return gestures.moveToCallerScreen(window.element, id: window.id, screen: screen)
        case .showUsage, .refreshUsage, .showAccountChooser, .showAssistantRead:
            let allowed = !WS2SilentUsageRead.startsModelTask && !assistant.turnStarted && !assistant.sessionStarted
            if allowed, case .showAssistantRead = request { runtime.openOwned() }
            return allowed
        case .showActivity:
            let before = activities.present
            return activities.present == before && !activities.startsPlayback
        case .showNativeStop(let id, let revision):
            let mark = assistant.showNativeStop(turnID: id, revision: revision)
            return mark == .showingNativeStop && assistant.stopMark != .stopped && !assistant.turnStarted
        case .setNextModel(let id, _):
            return assistant.setNextModel(id, allowed: allowedModels) && !assistant.turnStarted
        case .setNextEffort(let id, _):
            return assistant.setNextEffort(id, allowed: allowedEfforts) && !assistant.turnStarted
        case .steerDraft(let id, let revision):
            let mark = assistant.steer(id: id, revision: revision, boundSessionID: boundSessionID)
            return mark == .waitingForAck && assistant.steerMark != .acknowledged && !assistant.turnStarted
        case .collapseWindow(let id, let revision):
            guard let window, frozen(id, revision, window) else { return false }
            gestures.owner.shade(window.element, window.id)
            return true
        case .expandWindow(let id, let revision):
            guard let window, frozen(id, revision, window) else { return false }
            return gestures.owner.unshade(window.id)
        case .unlockNoted(let id):
            var handoff = WS2SilentUnlockHandoff()
            handoff.hand(id)
            return !handoff.unlocks && !handoff.synthesizesKeystroke && !handoff.callsPrivateUnlockAPI
        case .fillRefused(let id):
            var fill = WS2SilentFillHandoff()
            fill.refuse(id)
            return !fill.fillsPassword && !fill.holdsSecret && !fill.typesSecret
        case .deviceRead(let id):
            var pairing = WS2SilentDevicePairing()
            pairing.showStatus()
            return id == "device.status" && !pairing.bound && !pairing.sessionOpen && !pairing.talksToRadio
                && pairing.statusLine == "未知"
        case .carPlayUnavailable(let id):
            var receiver = WS2SilentCarPlayReceiver()
            if id == "carplay.exit" { receiver.exit() } else { receiver.enter() }
            guard !receiver.connected, !receiver.sessionStarted, receiver.line == "还不能接收" else { return false }
            return false
        case .challengeOnly(let id):
            guard let command = WS2SilentCatalog.lookup(id),
                  let outcome = WS2SilentChallenge.outcome(for: command) else { return false }
            return !outcome.unlocks && !outcome.fillsPassword
        case .showNamed(let id):
            switch WS2SilentSurface.surface(for: id) {
            case .settings(let page):
                gestures.owner.showSettingsWindow(section: section(page))
            case .windowBrowser:
                gestures.owner.openWindowBrowserPanel()
            case .readout:
                if id == "input.pause" {
                    gestures.owner.inputController.pauseHooks()
                    return gestures.owner.inputController.hooksPaused
                }
                if id == "privacy.cover" || id == "scene.conversation" {
                    return WS2SilentCover.cover(&cover)
                }
                if WS2SilentDraftCommand.handles(id) {
                    return WS2SilentDraftCommand.apply(id, targetID: "", revision: 0, to: &draft)
                }
            }
            return true
        case .intent(let id, let revision, let name):
            if WS2SilentDraftCommand.handles(name) {
                return WS2SilentDraftCommand.apply(name, targetID: id, revision: revision, to: &draft)
            }
            if let effect = WS2SilentWindowEffect.effect(for: name) {
                guard !effect.unlocks, !effect.entersSystemFullscreen else { return false }
                guard let window, frozen(id, revision, window) else { return false }
                return perform(effect, window: window, gestures: gestures)
            }
            _ = WS2SilentSim.record(name: name, target: id, revision: revision)
            return false
        case .waiting, .refused:
            return false
        }
    }

    private static func frozen(_ id: String, _ revision: UInt64, _ window: WindowTarget) -> Bool {
        WS2SilentProductPort.acceptsFrozenWindow(
            requestedID: id,
            requestedRevision: revision,
            liveID: String(window.id),
            liveRevision: window.revision)
    }

    private static func perform(
        _ effect: WS2SilentWindowEffect,
        window: WindowTarget,
        gestures: TrackpadGestureController
    ) -> Bool {
        let owner = gestures.owner
        let focused = focusedWindow().flatMap { windowID(of: $0) }
        let same = focused == window.id
        switch effect {
        case .tuck:
            guard same else { return false }
            return owner.notch.tuckFocused()
        case .untuck:
            guard owner.notch.isTucked(window.id) else { return false }
            owner.notch.release(window.id, reason: "silent")
            return !owner.notch.isTucked(window.id)
        case .magicTile:
            guard same else { return false }
            return owner.gestures.magicTile(main: window.id, element: window.element, announce: false)
        case .place, .collapse, .expand, .undo, .move, .glance:
            return false
        case .pin, .unpin, .slideOver, .leaveSlideOver, .pictureInPicture, .leavePictureInPicture,
             .choose, .chooseDisplay, .batchReview, .strip, .stripOverview, .scene:
            _ = WS2SilentSim.record(name: "\(effect)", target: String(window.id), revision: window.revision)
            return false
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
