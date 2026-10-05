// v4 增量验收的源码测试。AppKit、真机和资格审查不在这里算通过。
import Foundation
import Synchronization

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

final class DeltaClock: WS2Clock, Sendable {
    private let instant = Mutex<WS2.Instant>(.init(nanoseconds: 100))
    func now() -> WS2.Instant { instant.withLock { $0 } }
    func set(_ value: UInt64) { instant.withLock { $0 = .init(nanoseconds: value) } }
}

@main
struct DeltaReviewV4Tests {
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

    @MainActor
    static func main() {
        effects()
        session()
        pins()
        frames()
        drafts()
        pages()
        activities()
        identity()
        heads()
        report()
        if failures != 0 {
            print("\(failures) failed")
            exit(1)
        }
    }

    static func effects() {
        let covered = WS2SilentEffectJudge.cover(overlayCreated: true, commandID: "privacy.cover")
        expect(!covered.isCompleted && covered.notchLine != "已遮住" && covered == .unavailable("尚未遮住"),
               "A01 a cover factory never says 已遮住")
        let invoked = WS2SilentEffectJudge.glance(invoked: true, previewVisible: true)
        let skipped = WS2SilentEffectJudge.glance(invoked: false, previewVisible: true)
        expect(invoked.isCompleted && !skipped.isCompleted,
               "A02 a visible preview without the glance call is not completed")
        let refused = WS2SilentEffectJudge.focusStart(wasIdle: true, runningAfter: false)
        expect(!refused.isCompleted && refused.notchLine != "已开始专注",
               "A03 a refused focus start does not say it started")
        let pin = WS2SilentEffectJudge.pin(alreadyPreviewing: true)
        expect(pin.result == .alreadySatisfied("已在置顶") && !pin.start,
               "A04 an existing pin is already satisfied and does not restart")
        let glancePort = WS2SilentEffectJudge.glance(windowID: 4, invoked: true, visible: true)
        let glanceNoop = WS2SilentEffectJudge.glance(windowID: 4, invoked: false, visible: true)
        expect(glancePort.isCompleted && !glanceNoop.isCompleted,
               "A02 replacing the glance port with a no-op fails the positive result")
        let pinStarted = WS2SilentEffectJudge.pin(alreadyPreviewing: false, started: true)
        let pinNoop = WS2SilentEffectJudge.pin(alreadyPreviewing: false, started: false)
        expect(pinStarted == .waiting(1) && !pinStarted.isCompleted && !pinNoop.isCompleted,
               "A13 a pin port that does not start is not completed")
        let slideNoop = WS2SilentEffectJudge.asyncWindow(already: false, started: false, satisfied: "已在侧拉")
        expect(!slideNoop.isCompleted, "A16-style a window port that does not start is not completed")
        var ledger = WS2SilentOperationLedger()
        let id = ledger.begin(commandID: "window.left", targetID: "A")
        ledger.turnPage()
        expect(!ledger.finish(id: id, line: "已完成") && ledger.visible.isEmpty,
               "A05 a late receipt does not cover the new page")
    }

    static func session() {
        var more = WS2SilentSession()
        let preview = more.propose(commandID: "window.left", targetID: "A", targetRevision: 1, now: at(10))
        guard case .awaiting(let proposal) = preview else {
            expect(false, "A06 a placement waits")
            return
        }
        expect(more.noteShown(id: proposal.id, at: proposal.displayedAt), "A06 the preview is shown")
        more.invalidate()
        expect(more.confirm(proposal, gestureBeganAt: at(20), now: at(20), liveRevision: 1) == .rejected(.wrongProposal),
               "A06 more cancels the old placement")

        var pair = WS2SilentSession()
        let first = pair.propose(commandID: "window.left", targetID: "A", targetRevision: 1, now: at(1))
        let second = pair.propose(commandID: "window.left", targetID: "A", targetRevision: 1, now: at(1))
        guard case .awaiting(let older) = first, case .awaiting(let newer) = second else {
            expect(false, "A07 two proposals wait")
            return
        }
        expect(older.id != newer.id, "A07 same-instant proposals have different ids")
        expect(pair.confirmShown(older, gestureBeganAt: at(2), now: at(2), liveRevision: 1) == .rejected(.wrongProposal),
               "A07 the old id is rejected")

        var changed = WS2SilentSession()
        let waiting = changed.propose(commandID: "window.left", targetID: "A", targetRevision: 3, now: at(10))
        guard case .awaiting(let held) = waiting else {
            expect(false, "A08 a placement waits")
            return
        }
        expect(changed.confirmShown(held, gestureBeganAt: at(20), now: at(20), liveRevision: 4) == .rejected(.staleTarget),
               "A08 a changed target voids the proposal")
        expect(changed.confirmShown(held, gestureBeganAt: at(30), now: at(30), liveRevision: 3) == .rejected(.wrongProposal),
               "A08 the old id stays rejected after the target returns")

        var early = WS2SilentSession()
        let shown = early.propose(commandID: "window.left", targetID: "A", targetRevision: 1, now: at(100))
        guard case .awaiting(let live) = shown else {
            expect(false, "A09 a placement waits")
            return
        }
        expect(early.confirm(live, gestureBeganAt: at(110), now: at(110), liveRevision: 1) == .rejected(.notShown),
               "A09 a confirmation before the preview is shown is rejected")
        expect(early.confirmShown(live, gestureBeganAt: at(90), now: at(110), liveRevision: 1) == .rejected(.confirmationTooEarly),
               "A09 a gesture that started before display is rejected")
        expect(early.confirmShown(live, gestureBeganAt: at(500), now: at(100), liveRevision: 1) == .rejected(.confirmationInFuture),
               "A09 a future gesture is rejected")
        var late = WS2SilentSession()
        let timed = late.propose(commandID: "window.left", targetID: "A", targetRevision: 1, now: at(0))
        if case .awaiting(let timedProposal) = timed {
            expect(late.confirmShown(timedProposal, gestureBeganAt: at(8_000), now: at(8_000), liveRevision: 1) == .rejected(.expired),
                   "A09 the eight-second deadline rejects the proposal")
        } else {
            expect(false, "A09 the deadline probe waits")
        }

        var lab = WS2SilentLabLog()
        lab.ingestSimulatedNod()
        expect(lab.windowCalls == 0 && lab.backendCalls == 0 && lab.credentialCalls == 0 && WS2SilentLab.realEffectCount == 0,
               "A10 a simulated nod does not touch a real port")
    }

    static func pins() {
        let bound = WS2BoundWindow(displayID: 1, windowID: "A", generation: 4)
        expect(bound.affected(pointerDisplay: 2, focusedWindow: "B") == "A",
               "A11 a pointer on another display does not retarget the bound window")
        expect(bound.affected(pointerDisplay: 2, focusedWindow: "B") == "A",
               "A12 a newly focused window does not replace the bound target")
        var pins = WS2PinLaunch()
        expect(pins.start(pid: 7, window: "A", generation: 1) == "new", "A13 the first pin starts one session")
        expect(pins.start(pid: 7, window: "A", generation: 2) == "join" && pins.inflight.count == 1,
               "A13 a repeated pin joins the same session")
        expect(pins.start(pid: 8, window: "A", generation: 3) == "new",
               "A13 the same window id on another process is not the same session")
        expect(!pins.finish(pid: 7, window: "A", generation: 9) && pins.inflight[WS2PinLaunch.Key(pid: 7, window: "A")] == 1,
               "A14 an older completion does not clear the current start")
    }

    static func frames() {
        var quiet = PiPFrameGate(expectedGeneration: 2, windowID: 9, deadline: 1)
        expect(quiet.evaluate(now: 0.2, frameGeneration: 2, pixelCount: 0, displayReady: false, sessionMatches: true, observedWindow: 9) == nil,
               "A16 zero frames before the deadline keep waiting")
        expect(quiet.evaluate(now: 1, frameGeneration: 2, pixelCount: 0, displayReady: false, sessionMatches: true, observedWindow: 9) == .timedOut,
               "A16 zero frames at the deadline time out")
        expect(quiet.settled == .timedOut, "A16 the timeout is the only arrival")

        var late = PiPFrameGate(expectedGeneration: 2, windowID: 9, deadline: 1)
        expect(late.evaluate(now: 1.1, frameGeneration: 2, pixelCount: 4, displayReady: true, sessionMatches: true, observedWindow: 9) == .timedOut,
               "A17 a frame after the deadline is not ready")

        var stopped = PiPFrameGate(expectedGeneration: 2, windowID: 9, deadline: 5)
        expect(stopped.cancel() == .cancelled && stopped.cancel() == .cancelled,
               "A18 cancel settles once")
        expect(stopped.evaluate(now: 0, frameGeneration: 2, pixelCount: 4, displayReady: true, sessionMatches: true, observedWindow: 9) == .cancelled,
               "A18 a later frame does not complete a cancelled wait")

        var stale = PiPFrameGate(expectedGeneration: 2, windowID: 9, deadline: 5)
        expect(stale.evaluate(now: 0.2, frameGeneration: 1, pixelCount: 4, displayReady: true, sessionMatches: true, observedWindow: 9) == nil,
               "A19 an older capture generation is not ready")

        var ready = PiPFrameGate(expectedGeneration: 2, windowID: 9, deadline: 5)
        expect(ready.evaluate(now: 0.2, frameGeneration: 2, pixelCount: 4, displayReady: true, sessionMatches: true, observedWindow: 9) == .ready,
               "A20 the current generation can become ready")
        expect(ready.evaluate(now: 0.3, frameGeneration: 2, pixelCount: 0, displayReady: false, sessionMatches: false, observedWindow: 1) == .ready,
               "A20 a later callback does not replace ready")
    }

    static func drafts() {
        var sent = pendingDraft()
        let request = sent.1
        expect(sent.0.acknowledge(ack(request)) == .sent, "A21 the matching ack sends once")
        let again = sent.0.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "session-1")
        let line = WS2SilentDraftReceipt.execution(again)
        expect(again == .alreadySatisfied && line == .alreadySatisfied("已送出") && sent.0.mark == .sent,
               "A21 sending again is already satisfied and is not a failure")

        var adopted = pendingDraft()
        _ = adopted.0.acknowledge(ack(adopted.1))
        _ = adopted.0.adopt(id: "draft-1", revision: 1)
        expect(adopted.0.mark == .sent
               && adopted.0.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "session-1") == .alreadySatisfied,
               "A22 adopting the same revision does not reset the sent record")

        var dropped = pendingDraft()
        dropped.0.disconnect()
        expect(dropped.0.mark == .outcomeUnknown
               && dropped.0.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "session-1") == .refused,
               "A23 a disconnect stays unknown and does not allocate a new request")

        var other = pendingDraft()
        expect(other.0.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "session-2") == .refused
               && other.0.mark == .waitingForAck,
               "A24 another session does not reuse the in-flight request")

        var edited = pendingDraft()
        let editedID = edited.1
        _ = WS2SilentDraftCommand.apply("dictation.edit", targetID: "draft-1", revision: 1, to: &edited.0)
        expect(edited.0.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: nil) == .refused
               && edited.0.acknowledge(ack(editedID)) == .sent,
               "A25 editing and an empty session leave the original ack able to settle")
    }

    static func pendingDraft() -> (WS2SilentDraftHost, UInt64) {
        var draft = WS2SilentDraftHost()
        _ = draft.adopt(id: "draft-1", revision: 1)
        guard case .waitingForAck(let id) = draft.submit(
            commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "session-1") else {
            expect(false, "draft fixture waits")
            return (draft, 0)
        }
        return (draft, id)
    }

    static func ack(_ id: UInt64) -> WS2SilentDraftAck {
        WS2SilentDraftAck(requestID: id, draftID: "draft-1", sessionID: "session-1", revision: 1)
    }

    @MainActor
    static func pages() {
        let clock = DeltaClock()
        let displayA = WS2.DisplayID(value: 1)
        let displayB = WS2.DisplayID(value: 2)
        var locked = false
        let coordinator = InteractionCoordinator(
            bootID: UUID(),
            clock: clock,
            environment: { InteractionCoordinator.Environment(unlocked: !locked, displays: [displayA, displayB]) },
            cancel: { _, _ in })
        func request(_ owner: String, _ display: WS2.DisplayID, _ layer: WS2.Layer, at now: UInt64) -> WS2.LeaseRequest {
            WS2.LeaseRequest(
                ownerID: owner, display: display, layer: layer,
                requestedAt: WS2.Instant(nanoseconds: now),
                deadline: WS2.Instant(nanoseconds: 10_000),
                containsPrivateContent: true)
        }
        clock.set(100)
        guard case .acquired(let opened) = coordinator.acquire(request("silent", displayA, .opened, at: 100)) else {
            expect(false, "A26 the page acquires a lease")
            return
        }
        clock.set(200)
        guard case .acquired(let review) = coordinator.acquire(request("authorization", displayA, .authorization, at: 200)) else {
            expect(false, "A26 authorization takes the page")
            return
        }
        expect(!coordinator.isCurrent(opened) && coordinator.isCurrent(review),
               "A26 the old confirmation cannot run after authorization")

        let restored = WS2PageRestore(scroll: 40, selectedID: "win-1")
            .apply(ids: ["win-2", "win-1"], oldLease: opened.token.serial, newLease: review.token.serial)
        expect(restored.scroll == 40 && restored.selected == "win-1" && restored.leaseChanged && !restored.missing,
               "A27 scroll and selection return on a new lease")
        let missing = WS2PageRestore(scroll: 40, selectedID: "win-1")
            .apply(ids: ["win-9"], oldLease: 1, newLease: 2)
        expect(missing.selected == nil && missing.missing, "A28 a removed object stays missing")

        let shelf = WS2LockedShelf(scroll: 12, selectedID: "secret", privateLine: "草稿").locked()
        clock.set(300)
        coordinator.invalidate(.locked, at: clock.now())
        locked = true
        expect(!coordinator.isCurrent(review) && shelf.privateLine.isEmpty && shelf.selectedID == nil,
               "A29 lock drops the old lease and the private line")

        let second = InteractionCoordinator(
            bootID: UUID(),
            clock: clock,
            environment: { InteractionCoordinator.Environment(unlocked: true, displays: [displayA, displayB]) },
            cancel: { _, _ in })
        clock.set(400)
        guard case .acquired(let firstDisplay) = second.acquire(request("silent", displayA, .opened, at: 400)) else {
            expect(false, "A30 the first display acquires the only input")
            return
        }
        clock.set(500)
        let other = second.acquire(request("windowBrowser", displayB, .opened, at: 500))
        if case .busy = other, second.isCurrent(firstDisplay) {
            expect(true, "A30 another display does not bypass the single active input")
        } else {
            expect(false, "A30 another display does not bypass the single active input")
        }

        clock.set(600)
        let handoff = second.acquire(
            request("launchpad", displayA, .opened, at: 600),
            replacing: firstDisplay)
        if case .acquired(let next) = handoff {
            expect(!second.isCurrent(firstDisplay) && second.isCurrent(next) && next.ownerID == "launchpad",
                   "A15 launchpad replaces the exact current lease")
        } else {
            expect(false, "A15 launchpad handoff acquires the replacement lease")
        }
    }

    static func activities() {
        var board = WS2SilentActivityBoard()
        board.cardIDs = ["music", "route"]
        var cursor = WS2SilentActivityCursor()
        expect(cursor.showCard(0, ids: board.cardIDs) == "music", "A31 the first card is the real id")
        board.cardIDs = ["route", "battery"]
        expect(cursor.showCard(1, ids: board.cardIDs) == "battery" && !board.startsPlayback,
               "A31 reordering follows the card and reading does not start playback")
        board.cardIDs = []
        board.sourceConnected = false
        expect(WS2SilentReadout.sentence("ui.activities", activities: board) == "未连接",
               "A31 a disconnected source is not an empty list")
        board.sourceConnected = true
        expect(WS2SilentReadout.sentence("ui.activities", activities: board) == "没有",
               "A31 a connected empty list says 没有")

        var current = WS2SilentUsageSnapshot()
        current.accountEpoch = 2
        current.accountQuota = .provided(1)
        var stale = WS2SilentUsageSnapshot()
        stale.accountEpoch = 1
        stale.accountQuota = .provided(9)
        expect(WS2SilentUsageRead.merge(current: current, incoming: stale).accountQuota == .provided(1),
               "A32 an older account packet does not overwrite the current account")

        var assistant = WS2SilentAssistant()
        expect(assistant.setNextModel("gpt", allowed: ["gpt"]) && assistant.setNextEffort("low", allowed: ["low"])
               && !assistant.turnStarted && !assistant.sessionStarted,
               "A33 the next model and effort do not start a turn")

        let camera = WS2CameraSimulation.noCamera()
        expect(camera.line == "未知" && !camera.grantsUnlock && camera.centimeters == nil,
               "A34 an unsupported camera stays unknown and does not unlock")
        print("not_run A35 real head motion")
    }

    static func identity() {
        var round = WS2LivenessRound(cameraID: "built-in", streamOpen: true, evidenceKnown: true)
        round.noteCameraChange(to: "external")
        expect(!round.maySubmitToSystem, "A36 a camera change invalidates the round")
        var lost = WS2LivenessRound(cameraID: "built-in", streamOpen: true, evidenceKnown: true)
        lost.noteStreamLoss()
        expect(!lost.streamOpen && !lost.maySubmitToSystem, "A36 a lost stream invalidates the round")
        let unknown = WS2LivenessRound(cameraID: "built-in", streamOpen: true, evidenceKnown: false)
        expect(!unknown.maySubmitToSystem, "A37 unknown evidence does not grant a system submit")
        var unlocked = WS2LivenessRound(cameraID: "built-in", streamOpen: true, evidenceKnown: true)
        unlocked.noteNativeUnlock()
        expect(unlocked.cancelled && !unlocked.claimedUnlock && !unlocked.maySubmitToSystem,
               "A38 native unlock cancels this operation")
        var car = WS2SilentCarPlayReceiver()
        car.enter()
        expect(!car.connected && car.line == "还不能接收", "A39 CarPlay without a protocol does not connect")
    }

    static func heads() {
        func samples(_ pitch: [Double], _ yaw: [Double], step: UInt64 = 50) -> [WS2HeadSample] {
            zip(pitch, yaw).enumerated().map { index, pair in
                WS2HeadSample(
                    at: WS2.Instant(nanoseconds: UInt64(index) * step * WS2.Duration.millisecond),
                    pitchDown: pair.0,
                    yaw: pair.1)
            }
        }
        let pitch: [Double] = [0, 0, 0, 0, 0, 12, 22, 22, 14, 4, 0, 0, 0]
        let zeros = Array(repeating: 0.0, count: pitch.count)
        let yaw: [Double] = [0, 0, 0, 0, 0, 12, 24, 24, 10, 0, -12, -24, -24, -10, 0, 0, 0, 0]
        let nod = samples(pitch, zeros)
        var cases: [(String, [WS2HeadSample], WS2HeadRecognition.Kind?)] = [
            ("H01", nod, .nod),
            ("H02", samples(Array(repeating: 0, count: yaw.count), yaw), .shake),
            ("H03", samples(Array(repeating: 0, count: yaw.count), yaw.map { -$0 }), .shake),
            ("H04", samples(zeros, pitch), nil),
            ("H19", samples(Array(repeating: 0, count: 18), [0, 0, 0, 0, 0, 12, 24, 24, 12, -12, -24, -24, -12, 0, 0, 0, 0, 0]), .shake),
            ("H05", Array(nod.prefix(9)), nil),
            ("H06", samples(pitch, zeros, step: 5), nil),
            ("H07", samples(pitch, zeros, step: 500), nil),
            ("H08", Array(nod.dropFirst(4)), nil),
        ]
        var broken = nod
        broken[7].yaw = .nan
        cases.append(("H09", broken, nil))
        broken = nod
        broken[7].pitchDown = .infinity
        cases.append(("H10", broken, nil))
        broken = nod
        broken[7].at = broken[6].at
        cases.append(("H11", broken, nil))
        broken = nod
        broken[7].at = WS2.Instant(nanoseconds: 0)
        cases.append(("H12", broken, nil))
        broken = nod
        for index in 8..<broken.count {
            broken[index].at = WS2.Instant(nanoseconds: broken[index].at.nanoseconds + 1_000_000_000)
        }
        cases.append(("H13", broken, nil))
        broken = nod
        broken[9].pitchDown = -70
        cases.append(("H14", broken, nil))
        cases.append(("H15", [], nil))
        let repeated = pitch + Array(repeating: 0.0, count: 4) + Array(pitch.dropFirst(5))
        cases.append(("H16", samples(repeated, Array(repeating: 0, count: repeated.count)), nil))
        for item in cases {
            expect(WS2HeadGesture.recognize(item.1)?.kind == item.2, "\(item.0) head trace")
        }
        let early = WS2HeadRecognition(kind: .nod, startedAt: WS2.Instant(nanoseconds: 99))
        expect(!WS2HeadGesture.confirms(early, displayedAt: WS2.Instant(nanoseconds: 100)), "H17")
        let shake = WS2HeadRecognition(kind: .shake, startedAt: WS2.Instant(nanoseconds: 101))
        expect(!WS2HeadGesture.confirms(shake, displayedAt: WS2.Instant(nanoseconds: 100)), "H18")
    }

    static func report() {
        print("A40 source tests: ran")
        print("A40 AppKit: 未运行")
        print("A40 hardware: 未运行")
        print("A40 qualification: 未运行")
        print("A15 live temporary app: 未运行")
    }
}
