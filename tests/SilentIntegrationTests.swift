// r01–r04。没有窗口时活体用例印 not_run，不用内存布尔冒充完成。
import CoreGraphics
import Foundation

extension WS2SilentSession {
    nonisolated(unsafe) static var confirmShownSequence: UInt64 = 0

    mutating func confirmShown(
        _ proposal: Proposal,
        gestureBeganAt: WS2.Instant,
        now: WS2.Instant,
        liveRevision: UInt64
    ) -> Step {
        Self.confirmShownSequence &+= 1
        if Self.confirmShownSequence == 0 { Self.confirmShownSequence = 1 }
        _ = noteShown(id: proposal.id, at: proposal.displayedAt)
        return confirm(
            proposal,
            gestureBeganAt: gestureBeganAt,
            now: now,
            liveRevision: liveRevision,
            sequence: Self.confirmShownSequence)
    }
}

@main
struct SilentIntegrationTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("ok   \(message)")
        } else {
            failures += 1
            print("FAIL \(message)")
        }
    }

    static func at(_ milliseconds: UInt64) -> WS2.Instant {
        WS2.Instant(nanoseconds: milliseconds * WS2.Duration.millisecond)
    }

    static func main() {
        let name = CommandLine.arguments.dropFirst().first ?? "all"
        switch name {
        case "r01": receipts()
        case "r02": proposals()
        case "r03": launchpad()
        case "r04": windows()
        case "all":
            receipts()
            proposals()
            launchpad()
            windows()
        default:
            print("unknown case \(name)")
            exit(2)
        }
        if failures != 0 {
            print("\(failures) failed")
            exit(1)
        }
    }

    static func receipts() {
        expect(WS2SilentLab.realEffectCount == 0, "r01 lab has no effect port")
        let glance = WS2SilentEffectJudge.glance(invoked: false, previewVisible: false)
        expect(!glance.isCompleted && glance == .unavailable("没预览"), "r01 glance without a preview is not completed")
        let panelOnly = WS2SilentEffectJudge.glance(windowID: 9, invoked: true, visible: false)
        expect(!panelOnly.isCompleted && panelOnly == .waiting(1),
               "r01 glance invoked without a live first frame waits, not completed")
        let liveGlance = WS2SilentEffectJudge.glance(windowID: 9, invoked: true, visible: true)
        expect(liveGlance.isCompleted, "r01 glance with a live first frame is completed")
        let usage = WS2SilentEffectJudge.usageRefresh(protocolParsed: false)
        expect(!usage.isCompleted && usage == .displayed("未提供"), "r01 usage without a protocol response is not completed")
        let cover = WS2SilentEffectJudge.cover(overlayCreated: false, commandID: "privacy.cover")
        expect(!cover.isCompleted && cover == .unavailable("尚未遮住"), "r01 cover without an overlay is not completed")
        let coverPartial = WS2SilentEffectJudge.cover(
            overlayCreated: true, commandID: "privacy.cover", allScreensCovered: false, missingScreens: true)
        expect(!coverPartial.isCompleted && coverPartial == .displayed("还有屏没遮住"),
               "r01 cover with missing screens is partial, not completed")
        let coverDone = WS2SilentEffectJudge.cover(
            overlayCreated: true, commandID: "privacy.cover", allScreensCovered: true, missingScreens: false)
        expect(coverDone.isCompleted, "r01 cover observed on every requested screen is completed")
        let pulled = WS2SilentEffectJudge.placement(frameMatched: false, commandID: "window.left", targetID: "win-1")
        expect(!pulled.isCompleted, "r01 pulling the effect port fails the positive check")
        let hostSource = (try? String(contentsOfFile: "prototype/App/WS2SilentHost.swift", encoding: .utf8)) ?? ""
        expect(!hostSource.contains("confirmSimulatedNod"),
               "r01 Host no longer routes diagnostic simulated nods into accept/apply")
        let applySource = (try? String(contentsOfFile: "prototype/App/WS2SilentApply.swift", encoding: .utf8)) ?? ""
        expect(applySource.contains("isLive(") && !applySource.contains("panelFrame(for: window.id) != nil"),
               "r01 Apply.glance requires Glance.isLive, not panelFrame alone")
        expect(applySource.contains("silentPrivacyCover.coverAllScreens"),
               "r01 Apply.cover uses the per-screen privacy cover adapter")
    }

    static func proposals() {
        var session = WS2SilentSession()
        let first = session.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(1))
        let second = session.propose(commandID: "window.right", targetID: "win-1", targetRevision: 1, now: at(1))
        guard case .awaiting(let older) = first, case .awaiting(let newer) = second else {
            expect(false, "r02 two proposals wait")
            return
        }
        expect(older.id != newer.id, "r02 same-instant proposals have different ids")
        expect(session.confirmShown(older, gestureBeganAt: at(2), now: at(2), liveRevision: 1) == .rejected(.wrongProposal),
               "r02 the old handle cannot accept the new proposal")
        var late = WS2SilentSession()
        let waiting = late.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(0))
        guard case .awaiting(let held) = waiting else {
            expect(false, "r02 a proposal waits")
            return
        }
        expect(late.confirmShown(held, gestureBeganAt: at(30_000), now: at(30_000), liveRevision: 3) == .rejected(.expired),
               "r02 thirty seconds later rejects")
        expect(late.confirmShown(held, gestureBeganAt: at(120), now: at(120), liveRevision: 3) == .rejected(.wrongProposal),
               "r02 an expired proposal cannot be accepted again")
        var moved = WS2SilentSession()
        let preview = moved.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(100))
        guard case .awaiting(let proposal) = preview else {
            expect(false, "r02 a placement waits")
            return
        }
        expect(moved.confirmShown(proposal, gestureBeganAt: at(120), now: at(120), liveRevision: 4) == .rejected(.staleTarget),
               "r02 a changed target voids the proposal")
        expect(moved.confirmShown(proposal, gestureBeganAt: at(120), now: at(120), liveRevision: 3) == .rejected(.wrongProposal),
               "r02 the old proposal cannot be accepted after the target changes")
        moved.invalidate()
        expect(moved.confirmShown(proposal, gestureBeganAt: at(130), now: at(130), liveRevision: 3) == .rejected(.wrongProposal),
               "r02 invalidate keeps the proposal void")

        // R02：方便遮挡退出只清内存，不走需要授权的“揭开”。
        var cover = WS2SilentCover.State()
        expect(WS2SilentCover.cover(&cover, overlayCreated: true), "r02 an observed overlay marks covered")
        expect(cover.covered, "r02 covered flag comes from the observation")
        expect(!WS2SilentCover.reveal(&cover), "r02 the silent path still cannot reveal")
        WS2SilentCover.clearConvenience(&cover)
        expect(!cover.covered && !cover.scopeSelected, "r02 convenience clear resets covered and scope")
        expect(!WS2SilentCover.cover(&cover, overlayCreated: false), "r02 a bare call cannot re-mark covered")
        expect(WS2SilentCopy.line("privacy.clearCover") == "撤掉遮挡", "r02 the cover-clear chip has copy")
        let coverSource = (try? String(contentsOfFile: "prototype/App/WS2SilentPrivacyCover.swift", encoding: .utf8)) ?? ""
        expect(coverSource.contains("didChangeScreenParametersNotification")
               && coverSource.contains("addGlobalMonitorForEvents"),
               "r02 cover reconciles on display change and listens for Esc outside the app")
    }

    static func launchpad() {
        let missing = WS2SilentEffectJudge.launchpad(panelVisible: false, onFrozenScreen: true, commandID: "launcher.open")
        expect(!missing.isCompleted && missing == .unavailable("没打开"), "r03 a hidden panel is not completed")
        let otherScreen = WS2SilentEffectJudge.launchpad(panelVisible: true, onFrozenScreen: false, commandID: "launcher.open")
        expect(!otherScreen.isCompleted, "r03 a panel off the frozen screen is not completed")
        let shown = WS2SilentEffectJudge.launchpad(panelVisible: true, onFrozenScreen: true, commandID: "launcher.open")
        expect(shown.isCompleted, "r03 a panel on the frozen screen is completed")

        // R03：换页后旧回执不能改新页面；当前操作才拥有可见结果。
        var ledger = WS2SilentOperationLedger()
        let opA = ledger.begin(commandID: "window.glance", targetID: "9", captureGeneration: 1)
        expect(ledger.visible == "还在等", "r03 a new operation waits")
        ledger.turnPage()
        expect(ledger.finish(id: opA, line: "已完成") == false, "r03 an old page cannot update the new page")
        expect(ledger.visible.isEmpty, "r03 the new page stays untouched by the old report")
        let opB = ledger.begin(commandID: "window.pin", targetID: "9", captureGeneration: 2)
        expect(ledger.visible == "还在等", "r03 the current operation owns the visible line")
        expect(ledger.finish(id: opB, line: "已完成"), "r03 the current operation updates the visible line")
        expect(ledger.visible == "已完成", "r03 the visible line reflects the live operation")
        expect(ledger.finish(id: opA, line: "已完成") == false, "r03 a late finish for a cancelled operation is rejected")

        // R03：置顶派发用代次判新旧；旧代次不能冒领。
        var pin = WS2PinLaunch()
        expect(pin.start(pid: 1, window: "9", generation: 7) == "new", "r03 pin launch starts a new generation")
        expect(pin.start(pid: 1, window: "9", generation: 7) == "join", "r03 a duplicate launch joins the in-flight generation")
        expect(pin.finish(pid: 1, window: "9", generation: 8) == false, "r03 a stale pin generation cannot claim the launch")
        expect(pin.finish(pid: 1, window: "9", generation: 7), "r03 the current pin generation completes")
        expect(pin.start(pid: 1, window: "9", generation: 9) == "already", "r03 an already-previewing window reports already")

        let hostSource = (try? String(contentsOfFile: "prototype/App/WS2SilentHost.swift", encoding: .utf8)) ?? ""
        expect(hostSource.contains("watchAsyncEnd"), "r03 the host routes async window actions to one terminal watcher")
        let shadeSource = (try? String(contentsOfFile: "prototype/WindowShade.swift", encoding: .utf8)) ?? ""
        expect(shadeSource.contains("noteSilentFoldCompletion"), "r03 fold completion is recorded, not dropped")
        liveWindowNote("r03")
    }

    static func windows() {
        let unread = WS2SilentEffectJudge.placement(frameMatched: false, commandID: "window.left", targetID: "win-1")
        expect(!unread.isCompleted && unread.notchLine == "结果未确认", "r04 a placement without readback is not completed")
        let glance = WS2SilentEffectJudge.glance(invoked: false, previewVisible: false)
        expect(!glance.isCompleted, "r04 a glance without a preview is not completed")
        // R04：授权成功≠采集成功；管线计数必须接上，并出现在里程碑日志里。
        let faceSource = (try? String(contentsOfFile: "prototype/App/FaceObservationSource.swift", encoding: .utf8)) ?? ""
        expect(faceSource.contains("struct FacePipelineCounters")
               && faceSource.contains("func pipelineCounters()"),
               "r04 the capture pipeline exposes privacy-safe counters")
        let milestone = (try? String(contentsOfFile: "prototype/App/SilentMilestoneProbe.swift", encoding: .utf8)) ?? ""
        expect(milestone.contains("head-pipeline"), "r04 the milestone probe prints the pipeline counters")
        liveWindowNote("r04")
    }

    static func liveWindowNote(_ label: String) {
        let count = onScreenWindowCount()
        if count == 0 {
            print("not_run \(label) live window")
            return
        }
        let unread = WS2SilentEffectJudge.placement(frameMatched: false, commandID: "window.left", targetID: "live")
        expect(!unread.isCompleted, "\(label) a visible window is not completed without a frame readback")
    }

    static func onScreenWindowCount() -> Int {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        return info.filter { entry in
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            return layer == 0 && !owner.isEmpty
        }.count
    }
}
