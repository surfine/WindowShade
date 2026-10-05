// WindowShade 2.1 · 把已经决定的静音命令交给现有宿主。
// 这里不移动窗口、不打开启动台、不开始番茄钟。点头不够的事留在拒绝里。
import Foundation

enum WS2SilentWindowEffect: Equatable, Sendable {
    case place(WS2SilentPlacement)
    case collapse
    case expand
    case tuck
    case untuck
    case pin
    case unpin
    case slideOver
    case leaveSlideOver
    case pictureInPicture
    case leavePictureInPicture
    case glance
    case choose
    case chooseDisplay
    case move
    case undo
    case batchReview
    case magicTile
    case strip(Int)
    case stripOverview
    case scene(String)

    static func effect(for commandID: String) -> WS2SilentWindowEffect? {
        switch commandID {
        case "window.left": return .place(.leftHalf)
        case "window.right": return .place(.rightHalf)
        case "window.fill": return .place(.fill)
        case "window.center": return .place(.center)
        case "window.topLeft": return .place(.topLeft)
        case "window.topRight": return .place(.topRight)
        case "window.bottomLeft": return .place(.bottomLeft)
        case "window.bottomRight": return .place(.bottomRight)
        case "window.collapse": return .collapse
        case "window.expand": return .expand
        case "window.tuck": return .tuck
        case "window.untuck": return .untuck
        case "window.pin": return .pin
        case "window.unpin": return .unpin
        case "window.slideOver": return .slideOver
        case "window.leaveSlideOver": return .leaveSlideOver
        case "window.pip": return .pictureInPicture
        case "window.leavePip": return .leavePictureInPicture
        case "window.glance": return .glance
        case "window.choose": return .choose
        case "window.chooseDisplay": return .chooseDisplay
        case "window.moveToSelectedDisplay": return .move
        case "window.undo", "window.restore": return .undo
        case "window.batchReview": return .batchReview
        case "window.magicTile": return .magicTile
        case "window.stripPrevious": return .strip(-1)
        case "window.stripNext": return .strip(1)
        case "window.stripOverview": return .stripOverview
        case "scene.reading": return .scene("reading")
        case "scene.coding": return .scene("coding")
        case "scene.presentation": return .scene("presentation")
        case "scene.presenter": return .scene("presenter")
        case "scene.conversation": return .scene("conversation")
        case "scene.resumeWork": return .scene("resumeWork")
        case "scene.largeText": return .scene("largeText")
        case "scene.accessibility": return .scene("accessibility")
        default: return nil
        }
    }

    var entersSystemFullscreen: Bool { false }
    var unlocks: Bool { false }
}

/// 取消置顶能当场读到结果。置顶、侧拉、画中画可以开始，开始本身不是做成。
enum WS2SilentEngineGate {
    static func calls(_ id: String) -> Bool {
        id == "window.unpin"
    }

    static func awaitsObservation(_ id: String) -> Bool {
        switch id {
        case "window.pin", "window.slideOver", "window.leaveSlideOver", "window.pip", "window.leavePip":
            return true
        default:
            return false
        }
    }

    /// 还没有明确对象入口的场景。静音路径不调用，也不写成已经做成。
    static func unobservableFunction(_ id: String) -> String? {
        switch id {
        case "scene.reading", "scene.coding", "scene.presentation", "scene.presenter":
            return "prepareSavedLayout"
        default:
            return nil
        }
    }
}

enum WS2SilentSettingsPage: String, Equatable, Sendable {
    case appearance, windows, shortcuts, permissions, privacy, silent, general

    static func page(for commandID: String) -> WS2SilentSettingsPage? {
        switch commandID {
        case "settings.appearance": return .appearance
        case "settings.windows": return .windows
        case "settings.shortcuts": return .shortcuts
        case "settings.permissions": return .permissions
        case "settings.privacy": return .privacy
        case "settings.silent": return .silent
        case "ui.settings": return .general
        default: return nil
        }
    }
}

enum WS2SilentSelection {
    static let emptyLine = "还没选"

    static func needsChoice(_ id: String) -> Bool {
        switch id {
        case "launcher.openSelected", "app.activateSelected", "app.previous", "desktop.select",
             "credential.chooseAlias":
            return true
        default:
            return false
        }
    }

    /// 没有选中的对象。窗口编号不是 App，也不是桌面。这条路不打开 App，不切换桌面。
    static func opensSystem(_ id: String, chosen: String?) -> Bool {
        _ = (id, chosen)
        return false
    }
}

enum WS2SilentNav {
    static func delta(_ id: String) -> Int? {
        switch id {
        case "nav.next": return 1
        case "nav.previous", "nav.back": return -1
        default: return nil
        }
    }

    static func cancels(_ id: String) -> Bool { id == "nav.cancel" }
    static func selects(_ id: String) -> Bool { id == "nav.select" }

    /// 翻页或取消已经发生之后的那一句。不重复芯片上的名字。
    static func resultLine(_ id: String) -> String? {
        switch id {
        case "nav.next": return "已到下一项"
        case "nav.previous": return "已到上一项"
        case "nav.back": return "已返回"
        case "nav.cancel": return "已取消"
        default: return nil
        }
    }
}

enum WS2SilentSurface: Equatable, Sendable {
    case windowBrowser
    case settings(WS2SilentSettingsPage)
    case readout

    static func surface(for commandID: String) -> WS2SilentSurface {
        switch commandID {
        case "ui.windows", "window.choose", "window.batchReview", "app.showSwitcher":
            return .windowBrowser
        default:
            if let page = WS2SilentSettingsPage.page(for: commandID) { return .settings(page) }
            return .readout
        }
    }
}

enum WS2SilentBoundary {
    /// 任何静音命令的结果都不能解锁，也不能代填密码。挑战结果缺了，就当成会解锁，让测试失败。
    static func unlocksOrFillsPassword(_ request: WS2SilentHostRequest) -> Bool {
        switch request {
        case .challengeOnly(let id):
            guard let command = WS2SilentCatalog.lookup(id),
                  let outcome = WS2SilentChallenge.outcome(for: command) else { return true }
            return outcome.unlocks || outcome.fillsPassword
        case .showLaunchpad, .placeWindow, .showFocusStatus, .startFocus, .pauseFocus, .resumeFocus,
             .glance, .openLaunchpadFolder, .adoptDraft, .submitDraft, .undoWindow, .moveToCallerDisplay,
             .showUsage, .refreshUsage, .showAccountChooser, .showActivity, .showAssistantRead,
             .showNativeStop, .setNextModel, .setNextEffort, .steerDraft, .collapseWindow, .expandWindow,
             .showNamed, .intent, .waiting, .refused:
            return false
        case .unlockNoted(let id), .fillRefused(let id), .deviceRead(let id), .carPlayUnavailable(let id):
            guard let outcome = WS2SilentSecurity.outcome(id) else { return true }
            return outcome.unlocks || outcome.fillsPassword || outcome.typesSecret
                || outcome.deviceBound || outcome.carPlayConnected
        }
    }
}

enum WS2SilentLaunchDestination: String, Equatable, Sendable {
    case home, today, library, spotlight, back, dismiss, nextPage, previousPage
}

/// 和现有窗口排布同一套名字。铺满屏幕是可用桌面，不是系统全屏。
enum WS2SilentPlacement: String, Equatable, Sendable {
    case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight, center, fill
}

enum WS2SilentHostRequest: Equatable, Sendable {
    case showLaunchpad(WS2SilentLaunchDestination)
    case placeWindow(id: String, revision: UInt64, placement: WS2SilentPlacement)
    case showFocusStatus
    case startFocus
    case pauseFocus
    case resumeFocus
    case glance(id: String, revision: UInt64)
    case openLaunchpadFolder(id: String)
    case adoptDraft(id: String, revision: UInt64)
    case submitDraft(id: String, revision: UInt64)
    case undoWindow(id: String, revision: UInt64)
    /// 移到呼叫者给出的那块屏。没有这块屏就不移，也不另找旁边一块。
    case moveToCallerDisplay(id: String, revision: UInt64)
    case showUsage(WS2SilentUsageScope)
    case refreshUsage
    case showAccountChooser
    case showActivity(WS2SilentActivityKind)
    case showAssistantRead
    case showNativeStop(id: String, revision: UInt64)
    case setNextModel(id: String, revision: UInt64)
    case setNextEffort(id: String, revision: UInt64)
    case steerDraft(id: String, revision: UInt64)
    case collapseWindow(id: String, revision: UInt64)
    case expandWindow(id: String, revision: UInt64)
    /// 挑战自己的结果。不解锁，不代填。
    case challengeOnly(id: String)
    /// 记下交给系统确认，或明确自己不解开。不合成按键。
    case unlockNoted(id: String)
    /// 秘密不在这里。不输入，不保存。
    case fillRefused(id: String)
    /// 没有设备。不打开配对。
    case deviceRead(id: String)
    /// 接收器没连上。不开始会话。
    case carPlayUnavailable(id: String)
    /// 只把这一页摆出来。不开始播放、计时或模型任务。
    case showNamed(String)
    /// 记下这一笔意图。模拟时不碰系统窗口、不解锁。
    case intent(id: String, revision: UInt64, name: String)
    case waiting
    case refused(WS2SilentHostRefusal)
}

enum WS2SilentHostRefusal: Equatable, Sendable {
    case notReady
    case needsSystemConfirmation
    case unsupported
}

enum WS2SilentProductPort {
    static func request(for step: WS2SilentSession.Step) -> WS2SilentHostRequest {
        switch step {
        case .awaiting:
            return .waiting
        case .needsSystemConfirmation:
            return .refused(.needsSystemConfirmation)
        case .rejected:
            return .refused(.notReady)
        case .shown(let proposal):
            return shown(proposal)
        case .accepted(let proposal):
            return accepted(proposal)
        }
    }

    private static func shown(_ proposal: WS2SilentSession.Proposal) -> WS2SilentHostRequest {
        switch proposal.command.id {
        case "launcher.open", "launcher.home":
            return .showLaunchpad(.home)
        case "launcher.library":
            return .showLaunchpad(.library)
        case "launcher.today":
            return .showLaunchpad(.today)
        case "launcher.search":
            return .showLaunchpad(.spotlight)
        case "launcher.back":
            return .showLaunchpad(.back)
        case "launcher.dismiss":
            return .showLaunchpad(.dismiss)
        case "launcher.nextPage":
            return .showLaunchpad(.nextPage)
        case "launcher.previousPage":
            return .showLaunchpad(.previousPage)
        case "launcher.openFolder":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .openLaunchpadFolder(id: proposal.targetID)
        case "activity.focus":
            return .showFocusStatus
        case "activity.music":
            return .showActivity(.music)
        case "activity.battery":
            return .showActivity(.airPods)
        case "activity.airdrop":
            return .showActivity(.airDrop)
        case "activity.route":
            return .showActivity(.route)
        case "activity.recording":
            return .showActivity(.recording)
        case "usage.quota":
            return .showUsage(.accountQuota)
        case "usage.session":
            return .showUsage(.selectedThread)
        case "usage.context":
            return .showUsage(.selectedContext)
        case "usage.accountActivity":
            return .showUsage(.accountActivity)
        case "usage.refresh":
            return .refreshUsage
        case "usage.chooseAccount":
            return .showAccountChooser
        case "assistant.show", "assistant.status", "assistant.models", "assistant.effort",
             "assistant.review", "assistant.chooseSession", "assistant.showDiff":
            return .showAssistantRead
        case "auth.cancel", "auth.useSystem":
            return .challengeOnly(id: proposal.command.id)
        case "auth.settings", "auth.revokeSession":
            return .unlockNoted(id: proposal.command.id)
        case "credential.chooseAlias":
            return .fillRefused(id: proposal.command.id)
        case "device.status":
            return .deviceRead(id: proposal.command.id)
        case "window.glance":
            return .glance(id: proposal.targetID, revision: proposal.targetRevision)
        default:
            if proposal.command.requiresSystemConfirmation { return .refused(.needsSystemConfirmation) }
            if proposal.command.confirmation == .none {
                return .showNamed(proposal.command.id)
            }
            return .refused(.unsupported)
        }
    }

    private static func accepted(_ proposal: WS2SilentSession.Proposal) -> WS2SilentHostRequest {
        switch proposal.command.id {
        case "window.left":
            return place(proposal, .leftHalf)
        case "window.right":
            return place(proposal, .rightHalf)
        case "window.fill":
            return place(proposal, .fill)
        case "window.center":
            return place(proposal, .center)
        case "window.topLeft":
            return place(proposal, .topLeft)
        case "window.topRight":
            return place(proposal, .topRight)
        case "window.bottomLeft":
            return place(proposal, .bottomLeft)
        case "window.bottomRight":
            return place(proposal, .bottomRight)
        case "focus.start":
            return .startFocus
        case "focus.pause":
            return .pauseFocus
        case "focus.resume":
            return .resumeFocus
        case "dictation.adopt":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .adoptDraft(id: proposal.targetID, revision: proposal.targetRevision)
        case "assistant.sendDraft":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .submitDraft(id: proposal.targetID, revision: proposal.targetRevision)
        case "window.undo", "window.restore":
            return .undoWindow(id: proposal.targetID, revision: proposal.targetRevision)
        case "window.moveToSelectedDisplay":
            return .moveToCallerDisplay(id: proposal.targetID, revision: proposal.targetRevision)
        case "window.collapse":
            return .collapseWindow(id: proposal.targetID, revision: proposal.targetRevision)
        case "window.expand":
            return .expandWindow(id: proposal.targetID, revision: proposal.targetRevision)
        case "assistant.interrupt":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .showNativeStop(id: proposal.targetID, revision: proposal.targetRevision)
        case "assistant.setModel":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .setNextModel(id: proposal.targetID, revision: proposal.targetRevision)
        case "assistant.setEffort":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .setNextEffort(id: proposal.targetID, revision: proposal.targetRevision)
        case "assistant.steerDraft":
            guard !proposal.targetID.isEmpty else { return .refused(.unsupported) }
            return .steerDraft(id: proposal.targetID, revision: proposal.targetRevision)
        case "music.pause", "music.resume", "music.nextTrack":
            return .refused(.unsupported)
        case "carplay.enter", "carplay.exit":
            return .carPlayUnavailable(id: proposal.command.id)
        default:
            if proposal.command.requiresSystemConfirmation { return .refused(.needsSystemConfirmation) }
            return .intent(id: proposal.targetID, revision: proposal.targetRevision, name: proposal.command.id)
        }
    }

    private static func place(_ proposal: WS2SilentSession.Proposal, _ placement: WS2SilentPlacement) -> WS2SilentHostRequest {
        .placeWindow(id: proposal.targetID, revision: proposal.targetRevision, placement: placement)
    }

    /// 打开启动台用呼叫者指定的屏幕。这个类型没有「指针所在屏幕」。
    enum LaunchScreen: Equatable, Sendable {
        case caller
    }

    struct LaunchPresentation: Equatable, Sendable {
        var destination: WS2SilentLaunchDestination
        var screen: LaunchScreen
        /// 打开主画面时，已经开着就不收起。收起只属于明确的 dismiss。
        var dismissesIfAlreadyOpen: Bool
    }

    static func launchPresentation(_ destination: WS2SilentLaunchDestination) -> LaunchPresentation {
        LaunchPresentation(
            destination: destination,
            screen: .caller,
            dismissesIfAlreadyOpen: destination == .dismiss
        )
    }

    /// 和 WindowPlacementAction.leftHalf 同一个 raw value。只接受冻结的那一扇，版本没变。
    static func acceptsFrozenWindow(
        requestedID: String,
        requestedRevision: UInt64,
        liveID: String,
        liveRevision: UInt64
    ) -> Bool {
        requestedID == liveID && requestedRevision == liveRevision
    }

    /// 看看番茄钟只显示。空闲也不从这条变成开始。
    static func showsFocusWithoutStarting(_ request: WS2SilentHostRequest) -> Bool {
        if case .showFocusStatus = request { return true }
        return false
    }

    /// 看一眼不走到会抢焦点的开启。展开真窗口、换桌面、把窗口叫到前台，都不从这里发生。
    static func glanceActivatesWindow(id: String, revision: UInt64) -> Bool {
        _ = (id, revision)
        return false
    }

    /// 半屏、四角、铺满走现有分格；居中走现有「大小不变」那一条。都落在呼叫者给出的可见区域，不进系统全屏。
    enum WindowRoute: Equatable, Sendable {
        case tileVisibleFrame
        case centerKeepingSize
    }

    static func windowRoute(_ placement: WS2SilentPlacement) -> WindowRoute {
        switch placement {
        case .center:
            return .centerKeepingSize
        case .leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .fill:
            return .tileVisibleFrame
        }
    }

    /// 移屏只用呼叫者给出的屏幕。对不上这扇冻结的窗口就不移。
    static func canMoveToCallerDisplay(callerScreenProvided: Bool, windowMatches: Bool) -> Bool {
        callerScreenProvided && windowMatches
    }

    static func entersSystemFullscreen(_ placement: WS2SilentPlacement) -> Bool {
        switch placement {
        case .leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .center, .fill:
            return false
        }
    }
}
