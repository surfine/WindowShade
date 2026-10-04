// WindowShade 2.1 · 静音命令封闭目录。
// 条目来自 Silent Identity Spec v2 的 06_COMMANDS.json。这里只描述命令，不执行窗口、助手或解锁。
import Foundation

enum WS2SilentMode: String, Hashable, Sendable {
    case command, dictation, securityChallenge
}

enum WS2SilentEffect: String, Hashable, Sendable {
    case read, window, write, securityEffect, draft, state, nativeAction, authHandoff
}

enum WS2SilentConfirmation: String, Hashable, Sendable {
    case none
    case freshNodOrClick
    case nativeAuthorization
    case nativeExplicitConsent
    case freshTaskConfirmation
    case existingAuthorization
    case existingNativeControl
    case freshExplicitLockIntent
    case explicitCurrentLockIntent
}

struct WS2SilentCommand: Hashable, Sendable {
    var id: String
    var effect: WS2SilentEffect
    var confirmation: WS2SilentConfirmation
    var modes: Set<WS2SilentMode>
    var operation: String
    /// 重复识别仍是同一个目标状态。左半屏再来一次还是左半屏，不会反过来。
    var desired: String

    var acceptsNodOrClick: Bool {
        switch confirmation {
        case .freshNodOrClick, .freshTaskConfirmation: return true
        case .none, .nativeAuthorization, .nativeExplicitConsent, .existingAuthorization,
             .existingNativeControl, .freshExplicitLockIntent, .explicitCurrentLockIntent:
            return false
        }
    }

    var requiresSystemConfirmation: Bool {
        switch confirmation {
        case .nativeAuthorization, .nativeExplicitConsent, .existingAuthorization,
             .existingNativeControl, .freshExplicitLockIntent, .explicitCurrentLockIntent:
            return true
        case .none, .freshNodOrClick, .freshTaskConfirmation:
            return false
        }
    }
}

enum WS2SilentCatalog {
    static let commands: [WS2SilentCommand] = [
        WS2SilentCommand(id: "ui.windows", effect: .read, confirmation: .none, modes: [.command], operation: "showPage", desired: "showPage:page=windows"),
        WS2SilentCommand(id: "ui.activities", effect: .read, confirmation: .none, modes: [.command], operation: "showPage", desired: "showPage:page=activities"),
        WS2SilentCommand(id: "ui.usage", effect: .read, confirmation: .none, modes: [.command], operation: "showPage", desired: "showPage:page=usage"),
        WS2SilentCommand(id: "ui.settings", effect: .read, confirmation: .none, modes: [.command], operation: "showPage", desired: "showPage:page=settings"),
        WS2SilentCommand(id: "nav.previous", effect: .read, confirmation: .none, modes: [.command], operation: "previous", desired: "previous"),
        WS2SilentCommand(id: "nav.next", effect: .read, confirmation: .none, modes: [.command], operation: "next", desired: "next"),
        WS2SilentCommand(id: "nav.back", effect: .read, confirmation: .none, modes: [.command], operation: "back", desired: "back"),
        WS2SilentCommand(id: "nav.cancel", effect: .read, confirmation: .none, modes: [.command], operation: "cancel", desired: "cancel"),
        WS2SilentCommand(id: "nav.select", effect: .read, confirmation: .none, modes: [.command], operation: "openSelection", desired: "openSelection"),
        WS2SilentCommand(id: "nav.help", effect: .read, confirmation: .none, modes: [.command], operation: "showHelp", desired: "showHelp"),
        WS2SilentCommand(id: "settings.appearance", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=appearance"),
        WS2SilentCommand(id: "settings.windows", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=windows"),
        WS2SilentCommand(id: "settings.shortcuts", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=shortcuts"),
        WS2SilentCommand(id: "settings.permissions", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=permissions"),
        WS2SilentCommand(id: "settings.privacy", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=privacy"),
        WS2SilentCommand(id: "settings.silent", effect: .read, confirmation: .none, modes: [.command], operation: "show", desired: "show:destination=silentControl"),
        WS2SilentCommand(id: "window.left", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=leftHalf"),
        WS2SilentCommand(id: "window.right", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=rightHalf"),
        WS2SilentCommand(id: "window.fill", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=fillVisibleFrame"),
        WS2SilentCommand(id: "window.center", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=centerKeepingSize"),
        WS2SilentCommand(id: "window.topLeft", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=topLeftQuarter"),
        WS2SilentCommand(id: "window.topRight", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=topRightQuarter"),
        WS2SilentCommand(id: "window.bottomLeft", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=bottomLeftQuarter"),
        WS2SilentCommand(id: "window.bottomRight", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlacement", desired: "setPlacement:placement=bottomRightQuarter"),
        WS2SilentCommand(id: "window.restore", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "restoreOwnedPlacement", desired: "restoreOwnedPlacement"),
        WS2SilentCommand(id: "window.collapse", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setCollapsed", desired: "setCollapsed:collapsed=true"),
        WS2SilentCommand(id: "window.expand", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setCollapsed", desired: "setCollapsed:collapsed=false"),
        WS2SilentCommand(id: "window.tuck", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setTucked", desired: "setTucked:tucked=true"),
        WS2SilentCommand(id: "window.untuck", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setTucked", desired: "setTucked:tucked=false"),
        WS2SilentCommand(id: "window.pin", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPinned", desired: "setPinned:pinned=true"),
        WS2SilentCommand(id: "window.unpin", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPinned", desired: "setPinned:pinned=false"),
        WS2SilentCommand(id: "window.slideOver", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setSlideOver", desired: "setSlideOver:enabled=true"),
        WS2SilentCommand(id: "window.leaveSlideOver", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setSlideOver", desired: "setSlideOver:enabled=false"),
        WS2SilentCommand(id: "window.pip", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPictureInPicture", desired: "setPictureInPicture:enabled=true"),
        WS2SilentCommand(id: "window.leavePip", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "setPictureInPicture", desired: "setPictureInPicture:enabled=false"),
        WS2SilentCommand(id: "window.glance", effect: .read, confirmation: .none, modes: [.command], operation: "showGlance", desired: "showGlance"),
        WS2SilentCommand(id: "window.choose", effect: .read, confirmation: .none, modes: [.command], operation: "showChooser", desired: "showChooser"),
        WS2SilentCommand(id: "window.chooseDisplay", effect: .read, confirmation: .none, modes: [.command], operation: "showDisplayChooser", desired: "showDisplayChooser"),
        WS2SilentCommand(id: "window.moveToSelectedDisplay", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "moveToSelectedDisplay", desired: "moveToSelectedDisplay"),
        WS2SilentCommand(id: "window.undo", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "undoOwnedReceipt", desired: "undoOwnedReceipt"),
        WS2SilentCommand(id: "window.batchReview", effect: .read, confirmation: .none, modes: [.command], operation: "showBatchPreview", desired: "showBatchPreview"),
        WS2SilentCommand(id: "activity.music", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=music"),
        WS2SilentCommand(id: "activity.battery", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=airPods"),
        WS2SilentCommand(id: "activity.airdrop", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=airDrop"),
        WS2SilentCommand(id: "activity.route", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=route"),
        WS2SilentCommand(id: "activity.recording", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=recording"),
        WS2SilentCommand(id: "activity.focus", effect: .read, confirmation: .none, modes: [.command], operation: "showKind", desired: "showKind:kind=focus"),
        WS2SilentCommand(id: "activity.previous", effect: .read, confirmation: .none, modes: [.command], operation: "moveSelection", desired: "moveSelection:delta=-1"),
        WS2SilentCommand(id: "activity.next", effect: .read, confirmation: .none, modes: [.command], operation: "moveSelection", desired: "moveSelection:delta=1"),
        WS2SilentCommand(id: "activity.details", effect: .read, confirmation: .none, modes: [.command], operation: "showDetails", desired: "showDetails"),
        WS2SilentCommand(id: "music.pause", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlayback", desired: "setPlayback:state=paused"),
        WS2SilentCommand(id: "music.resume", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "setPlayback", desired: "setPlayback:state=playing"),
        WS2SilentCommand(id: "music.nextTrack", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "nextTrack", desired: "nextTrack"),
        WS2SilentCommand(id: "focus.start", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "start", desired: "start"),
        WS2SilentCommand(id: "focus.pause", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "pause", desired: "pause"),
        WS2SilentCommand(id: "focus.resume", effect: .state, confirmation: .freshNodOrClick, modes: [.command], operation: "resume", desired: "resume"),
        WS2SilentCommand(id: "usage.quota", effect: .read, confirmation: .none, modes: [.command], operation: "showScope", desired: "showScope:scope=accountQuota"),
        WS2SilentCommand(id: "usage.session", effect: .read, confirmation: .none, modes: [.command], operation: "showScope", desired: "showScope:scope=selectedThread"),
        WS2SilentCommand(id: "usage.context", effect: .read, confirmation: .none, modes: [.command], operation: "showScope", desired: "showScope:scope=selectedContext"),
        WS2SilentCommand(id: "usage.accountActivity", effect: .read, confirmation: .none, modes: [.command], operation: "showScope", desired: "showScope:scope=accountActivity"),
        WS2SilentCommand(id: "usage.refresh", effect: .read, confirmation: .none, modes: [.command], operation: "refreshReadOnly", desired: "refreshReadOnly"),
        WS2SilentCommand(id: "usage.chooseAccount", effect: .read, confirmation: .none, modes: [.command], operation: "showConnectedAccountChooser", desired: "showConnectedAccountChooser"),
        WS2SilentCommand(id: "assistant.show", effect: .read, confirmation: .none, modes: [.command], operation: "showSessions", desired: "showSessions"),
        WS2SilentCommand(id: "assistant.status", effect: .read, confirmation: .none, modes: [.command], operation: "showStatus", desired: "showStatus"),
        WS2SilentCommand(id: "assistant.models", effect: .read, confirmation: .none, modes: [.command], operation: "showModelPicker", desired: "showModelPicker"),
        WS2SilentCommand(id: "assistant.effort", effect: .read, confirmation: .none, modes: [.command], operation: "showEffortPicker", desired: "showEffortPicker"),
        WS2SilentCommand(id: "assistant.review", effect: .read, confirmation: .none, modes: [.command], operation: "showReview", desired: "showReview"),
        WS2SilentCommand(id: "assistant.source", effect: .read, confirmation: .freshNodOrClick, modes: [.command], operation: "openSource", desired: "openSource"),
        WS2SilentCommand(id: "assistant.interrupt", effect: .nativeAction, confirmation: .freshTaskConfirmation, modes: [.command], operation: "requestBoundInterrupt", desired: "requestBoundInterrupt"),
        WS2SilentCommand(id: "privacy.cover", effect: .state, confirmation: .none, modes: [.command], operation: "coverSelectedScope", desired: "coverSelectedScope"),
        WS2SilentCommand(id: "privacy.reveal", effect: .authHandoff, confirmation: .existingAuthorization, modes: [.command], operation: "requestReveal", desired: "requestReveal"),
        WS2SilentCommand(id: "privacy.status", effect: .read, confirmation: .none, modes: [.command], operation: "showStatus", desired: "showStatus"),
        WS2SilentCommand(id: "input.pause", effect: .state, confirmation: .none, modes: [.command], operation: "pause", desired: "pause"),
        WS2SilentCommand(id: "input.recenter", effect: .nativeAction, confirmation: .existingNativeControl, modes: [.command], operation: "requestCalibration", desired: "requestCalibration"),
        WS2SilentCommand(id: "input.profile", effect: .read, confirmation: .none, modes: [.command], operation: "showProfiles", desired: "showProfiles"),
        WS2SilentCommand(id: "scene.reading", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "prepareSavedLayout", desired: "prepareSavedLayout:preset=reading"),
        WS2SilentCommand(id: "scene.coding", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "prepareSavedLayout", desired: "prepareSavedLayout:preset=coding"),
        WS2SilentCommand(id: "scene.presentation", effect: .window, confirmation: .freshNodOrClick, modes: [.command], operation: "prepareSavedLayout", desired: "prepareSavedLayout:preset=presentation"),
        WS2SilentCommand(id: "launcher.open", effect: .read, confirmation: .none, modes: [.command], operation: "setHomeVisible", desired: "setHomeVisible"),
        WS2SilentCommand(id: "launcher.home", effect: .read, confirmation: .none, modes: [.command], operation: "navigateHome", desired: "navigateHome"),
        WS2SilentCommand(id: "launcher.library", effect: .read, confirmation: .none, modes: [.command], operation: "navigateLibrary", desired: "navigateLibrary"),
        WS2SilentCommand(id: "launcher.today", effect: .read, confirmation: .none, modes: [.command], operation: "navigateToday", desired: "navigateToday"),
        WS2SilentCommand(id: "launcher.search", effect: .read, confirmation: .none, modes: [.command], operation: "showConfirmedSearch", desired: "showConfirmedSearch"),
        WS2SilentCommand(id: "launcher.nextPage", effect: .read, confirmation: .none, modes: [.command], operation: "nextPage", desired: "nextPage"),
        WS2SilentCommand(id: "launcher.previousPage", effect: .read, confirmation: .none, modes: [.command], operation: "previousPage", desired: "previousPage"),
        WS2SilentCommand(id: "launcher.back", effect: .read, confirmation: .none, modes: [.command], operation: "backOneLevel", desired: "backOneLevel"),
        WS2SilentCommand(id: "launcher.dismiss", effect: .read, confirmation: .none, modes: [.command], operation: "dismissRestoreOrigin", desired: "dismissRestoreOrigin"),
        WS2SilentCommand(id: "launcher.openSelected", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "openCatalogSelection", desired: "openCatalogSelection"),
        WS2SilentCommand(id: "launcher.openFolder", effect: .read, confirmation: .none, modes: [.command], operation: "openSelectedFolder", desired: "openSelectedFolder"),
        WS2SilentCommand(id: "app.showSwitcher", effect: .read, confirmation: .none, modes: [.command], operation: "showSwitcher", desired: "showSwitcher"),
        WS2SilentCommand(id: "app.activateSelected", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "activateSelection", desired: "activateSelection"),
        WS2SilentCommand(id: "app.previous", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "activatePreviousBound", desired: "activatePreviousBound"),
        WS2SilentCommand(id: "desktop.showSwitcher", effect: .read, confirmation: .none, modes: [.command], operation: "showSpaces", desired: "showSpaces"),
        WS2SilentCommand(id: "desktop.select", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "activateBoundSpace", desired: "activateBoundSpace"),
        WS2SilentCommand(id: "desktop.missionControl", effect: .read, confirmation: .none, modes: [.command], operation: "openMissionControl", desired: "openMissionControl"),
        WS2SilentCommand(id: "desktop.showDesktop", effect: .read, confirmation: .none, modes: [.command], operation: "showDesktop", desired: "showDesktop"),
        WS2SilentCommand(id: "window.magicTile", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "prepareMagicTiling", desired: "prepareMagicTiling"),
        WS2SilentCommand(id: "window.stripPrevious", effect: .read, confirmation: .none, modes: [.command], operation: "selectPreviousStripColumn", desired: "selectPreviousStripColumn"),
        WS2SilentCommand(id: "window.stripNext", effect: .read, confirmation: .none, modes: [.command], operation: "selectNextStripColumn", desired: "selectNextStripColumn"),
        WS2SilentCommand(id: "window.stripOverview", effect: .read, confirmation: .none, modes: [.command], operation: "showStripOverview", desired: "showStripOverview"),
        WS2SilentCommand(id: "dictation.start", effect: .draft, confirmation: .none, modes: [.command, .dictation], operation: "beginSilentDraft", desired: "beginSilentDraft"),
        WS2SilentCommand(id: "dictation.stopCapture", effect: .draft, confirmation: .none, modes: [.command, .dictation], operation: "endCapture", desired: "endCapture"),
        WS2SilentCommand(id: "dictation.nextCandidate", effect: .draft, confirmation: .none, modes: [.command, .dictation], operation: "nextCandidate", desired: "nextCandidate"),
        WS2SilentCommand(id: "dictation.retry", effect: .draft, confirmation: .none, modes: [.command, .dictation], operation: "rerecord", desired: "rerecord"),
        WS2SilentCommand(id: "dictation.adopt", effect: .draft, confirmation: .freshNodOrClick, modes: [.command, .dictation], operation: "adoptDraft", desired: "adoptDraft"),
        WS2SilentCommand(id: "dictation.edit", effect: .draft, confirmation: .none, modes: [.command, .dictation], operation: "showEditor", desired: "showEditor"),
        WS2SilentCommand(id: "dictation.insertPhrase", effect: .draft, confirmation: .freshNodOrClick, modes: [.command, .dictation], operation: "insertRegisteredPhrase", desired: "insertRegisteredPhrase"),
        WS2SilentCommand(id: "dictation.discard", effect: .draft, confirmation: .freshNodOrClick, modes: [.command, .dictation], operation: "discardDraft", desired: "discardDraft"),
        WS2SilentCommand(id: "dictation.enableWhisper", effect: .draft, confirmation: .nativeExplicitConsent, modes: [.command, .dictation], operation: "requestExplicitAudioMode", desired: "requestExplicitAudioMode"),
        WS2SilentCommand(id: "assistant.chooseSession", effect: .read, confirmation: .none, modes: [.command], operation: "chooseBoundSession", desired: "chooseBoundSession"),
        WS2SilentCommand(id: "assistant.setModel", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "setNextModel", desired: "setNextModel"),
        WS2SilentCommand(id: "assistant.setEffort", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "setNextEffort", desired: "setNextEffort"),
        WS2SilentCommand(id: "assistant.sendDraft", effect: .write, confirmation: .freshTaskConfirmation, modes: [.command], operation: "submitDraftOnce", desired: "submitDraftOnce"),
        WS2SilentCommand(id: "assistant.steerDraft", effect: .write, confirmation: .freshTaskConfirmation, modes: [.command], operation: "steerExpectedTurn", desired: "steerExpectedTurn"),
        WS2SilentCommand(id: "assistant.showDiff", effect: .read, confirmation: .none, modes: [.command], operation: "openExistingDiff", desired: "openExistingDiff"),
        WS2SilentCommand(id: "assistant.requestApproval", effect: .read, confirmation: .existingAuthorization, modes: [.command], operation: "handoffNativeApproval", desired: "handoffNativeApproval"),
        WS2SilentCommand(id: "scene.conversation", effect: .read, confirmation: .none, modes: [.command], operation: "pauseAndCoverSelected", desired: "pauseAndCoverSelected"),
        WS2SilentCommand(id: "scene.resumeWork", effect: .write, confirmation: .existingAuthorization, modes: [.command], operation: "requestOwnedSceneRestore", desired: "requestOwnedSceneRestore"),
        WS2SilentCommand(id: "scene.presenter", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "preparePresenterDisplay", desired: "preparePresenterDisplay"),
        WS2SilentCommand(id: "scene.largeText", effect: .read, confirmation: .none, modes: [.command], operation: "setLargeText", desired: "setLargeText"),
        WS2SilentCommand(id: "scene.accessibility", effect: .read, confirmation: .none, modes: [.command], operation: "openAccessibleInput", desired: "openAccessibleInput"),
        WS2SilentCommand(id: "privacy.panicLock", effect: .securityEffect, confirmation: .freshExplicitLockIntent, modes: [.command], operation: "requestPanicSystemLock", desired: "requestPanicSystemLock"),
        WS2SilentCommand(id: "privacy.awaySummary", effect: .read, confirmation: .none, modes: [.command], operation: "showActualAwaySummary", desired: "showActualAwaySummary"),
        WS2SilentCommand(id: "privacy.selectScope", effect: .read, confirmation: .none, modes: [.command], operation: "showProtectionScope", desired: "showProtectionScope"),
        WS2SilentCommand(id: "auth.settings", effect: .securityEffect, confirmation: .none, modes: [.command], operation: "openSettings", desired: "openSettings"),
        WS2SilentCommand(id: "auth.enroll", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "beginAuthenticatedEnrollment", desired: "beginAuthenticatedEnrollment"),
        WS2SilentCommand(id: "auth.deleteEnrollment", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "deleteAuthenticatedEnrollment", desired: "deleteAuthenticatedEnrollment"),
        WS2SilentCommand(id: "auth.begin", effect: .securityEffect, confirmation: .explicitCurrentLockIntent, modes: [.securityChallenge], operation: "beginFreshAttempt", desired: "beginFreshAttempt"),
        WS2SilentCommand(id: "auth.cancel", effect: .securityEffect, confirmation: .none, modes: [.securityChallenge], operation: "cancelCurrentAttempt", desired: "cancelCurrentAttempt"),
        WS2SilentCommand(id: "auth.useSystem", effect: .securityEffect, confirmation: .none, modes: [.securityChallenge], operation: "yieldToSystem", desired: "yieldToSystem"),
        WS2SilentCommand(id: "auth.authorizeSession", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "authorizeCredentialSession", desired: "authorizeCredentialSession"),
        WS2SilentCommand(id: "auth.revokeSession", effect: .securityEffect, confirmation: .none, modes: [.command], operation: "revokeCredentialSession", desired: "revokeCredentialSession"),
        WS2SilentCommand(id: "auth.lab", effect: .securityEffect, confirmation: .nativeExplicitConsent, modes: [.command], operation: "openAnalysisOnlyLab", desired: "openAnalysisOnlyLab"),
        WS2SilentCommand(id: "auth.profiles", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "manageChallengeProfiles", desired: "manageChallengeProfiles"),
        WS2SilentCommand(id: "device.bind", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "beginAuthenticatedNativePairing", desired: "beginAuthenticatedNativePairing"),
        WS2SilentCommand(id: "device.revoke", effect: .securityEffect, confirmation: .nativeAuthorization, modes: [.command], operation: "revokeBoundDevice", desired: "revokeBoundDevice"),
        WS2SilentCommand(id: "device.status", effect: .read, confirmation: .none, modes: [.command], operation: "showEvidenceClass", desired: "showEvidenceClass"),
        WS2SilentCommand(id: "device.range", effect: .read, confirmation: .nativeExplicitConsent, modes: [.command], operation: "showProximityCalibration", desired: "showProximityCalibration"),
        WS2SilentCommand(id: "credential.chooseAlias", effect: .read, confirmation: .none, modes: [.command], operation: "chooseRegisteredAlias", desired: "chooseRegisteredAlias"),
        WS2SilentCommand(id: "credential.secretPhraseLab", effect: .draft, confirmation: .nativeExplicitConsent, modes: [.command], operation: "openIsolatedSecretPhraseLab", desired: "openIsolatedSecretPhraseLab"),
        WS2SilentCommand(id: "carplay.enter", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "enterQualifiedReceiver", desired: "enterQualifiedReceiver"),
        WS2SilentCommand(id: "carplay.exit", effect: .write, confirmation: .freshNodOrClick, modes: [.command], operation: "exitReceiverPreserveDesktop", desired: "exitReceiverPreserveDesktop"),
    ]

    private static let index: [String: WS2SilentCommand] = {
        Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
    }()

    static func lookup(_ id: String) -> WS2SilentCommand? { index[id] }
    static var count: Int { commands.count }
}
