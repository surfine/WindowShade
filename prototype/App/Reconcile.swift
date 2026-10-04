// 折叠会话监控（Reconcile）：周期性核对真实窗口与卷帘条状态，
// 处理外部唤回、窗口丢失与异常清理。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func updateReconcileTimer() {
        let shouldRun = !shaded.isEmpty || !shadeJournalEntries().isEmpty
        if shouldRun {
            guard reconcileTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: shadedWindowReconcileInterval,
                                             repeats: true) { [weak self] _ in
                self?.reconcileShadedWindows(reason: "timer")
            }
            timer.tolerance = 1.5
            reconcileTimer = timer
            wlog("reconcile: timer started")
        } else if let timer = reconcileTimer {
            timer.invalidate()
            reconcileTimer = nil
            lastJournalRescueAttempt = nil
            wlog("reconcile: timer stopped")
        }
    }
    func shouldRetryJournalRescue(now: Date) -> Bool {
        guard !shadeJournalEntries().isEmpty else { return false }
        guard let last = lastJournalRescueAttempt else { return true }
        return now.timeIntervalSince(last) >= journalRescueRetryInterval
    }
    func sourceWindowLooksUserVisible(state: ShadeState, pos: CGPoint, size: CGSize,
                                              onScreenWindowIDs: Set<CGWindowID>? = nil,
                                              sourceIsMinimized: Bool? = nil) -> Bool {
        guard windowIsVisible(pos: pos, size: size) else { return false }
        let sourceOnScreen = onScreenWindowIDs?.contains(state.sourceWindowID)
            ?? cgWindowIsCurrentlyOnScreen(state.sourceWindowID)
        guard sourceOnScreen else { return false }
        switch state.hide {
        case .quickLookClosed:
            return false
        case .none:
            return false
        case .offscreen, .privateOffscreen:
            return Date() >= state.ignoreAppRevealUntil
        case .privateAlpha:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            let sampledAlpha = PrivateSLSWindowMover.shared.windowAlpha(id: state.sourceWindowID)
                ?? (cgWindowInfo(state.sourceWindowID)?[kCGWindowAlpha as String] as? NSNumber).map { $0.floatValue }
            guard let alpha = sampledAlpha, alpha.isFinite, (0...1).contains(alpha) else { return false }
            return alpha > 0.05
        case .hidden:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            // 看一眼在画面下面临时取消隐藏：那不是用户唤回。
            guard !MainActor.assumeIsolated({ glance.holdsReveal(state.sourceWindowID) }) else { return false }
            guard let app = runningApp(pid: state.pid), !app.isTerminated else { return false }
            return !app.isHidden
        case .minimized:
            // AX 快照读取在后台工作队列；没有快照时保守地认为仍不可见，
            // 不能为了确认菜单/定时器状态回到主线程同步 IPC。
            return sourceIsMinimized.map { !$0 } ?? false
        case .ownWindowOrderedOut:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            return ownWindow(id: state.sourceWindowID)?.isVisible ?? false
        }
    }
    func shouldLogReconcileInvalidCount(_ count: Int) -> Bool {
        count == 1 || count == 3 || count == 10 || count % 60 == 0
    }
    func sourceWindowMissingShouldCleanup(id: CGWindowID, state: ShadeState) -> Bool {
        guard runningApp(pid: state.pid) != nil else {
            wlog("reconcile: source app gone id=\(id) app=\(state.appName)")
            return true
        }

        let count = (reconcileInvalidCounts[id] ?? 0) + 1
        reconcileInvalidCounts[id] = count

        switch state.hide {
        case .hidden, .minimized, .offscreen, .privateOffscreen, .privateAlpha, .ownWindowOrderedOut, .quickLookClosed:
            if shouldLogReconcileInvalidCount(count) {
                wlog("reconcile: source geometry unavailable id=\(id) app=\(state.appName) hide=\(state.hide.rawValue) count=\(count)")
            }
            return false
        case .none:
            // Repeated AX failure still does not prove that a live app's window closed.
            if shouldLogReconcileInvalidCount(count) {
                wlog("reconcile: native source unknown id=\(id) count=\(count); recovery retained")
            }
            return false
        }
    }
    func reconcileShadedWindows(reason: String) {
        guard !isReconcilingShadedWindows else { return }
        isReconcilingShadedWindows = true
        defer { isReconcilingShadedWindows = false }

        guard MainActor.assumeIsolated({ AuthorizationService.shared.lockState() == .unlocked }) else {
            axReadGate.setEnabled(false)
            updateReconcileTimer()
            return
        }
        pruneShadeJournal(reason: "reconcile-\(reason)")

        guard AXIsProcessTrusted() else {
            axReadGate.setEnabled(false)
            updateReconcileTimer()
            return
        }
        if ownsGlobalInput, eventTap == nil, setupEventTap() {
            wlog("reconcile: event tap restored")
        }

        let now = Date()
        if shaded.isEmpty {
            if shouldRetryJournalRescue(now: now) {
                lastJournalRescueAttempt = now
                rescueOffscreenWindows(silent: true)
            }
            axReadGate.setEnabled(true)
            axReadGate.replaceWanted([pid_t]())
            updateReconcileTimer()
            return
        }

        pumpReconcileAXReads(reason: reason, refreshWanted: true)
    }

    func reconcileAXApplicationIDs() -> [pid_t] {
        var seen: Set<pid_t> = []
        var ids: [pid_t] = []
        for state in shaded.values where seen.insert(state.pid).inserted {
            ids.append(state.pid)
        }
        ids.sort()
        return ids
    }

    /// 只发还没在途、且名额还够的 App。一个 App 没回来，不重发，也不挡住别的 App。
    /// 刚返回的 App 要等下一次巡检才再排队，避免读完立刻再读。
    func pumpReconcileAXReads(reason: String, refreshWanted: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now.isFinite else { return }
        let unlocked = MainActor.assumeIsolated({ AuthorizationService.shared.lockState() == .unlocked })
        guard unlocked, AXIsProcessTrusted() else {
            axReadGate.setEnabled(false)
            return
        }
        axReadGate.setEnabled(true)
        let voided = axReadGate.voidExpired(now: now, lifetime: AXReadGate<pid_t, [WS2FoldCallbackStamp]>.resultLifetime)
        for ticket in voided {
            let age = Int((now - ticket.admittedAt) * 1000)
            wlog("reconcile: ax result void pid=\(ticket.app) occupied=\(axReadGate.occupiedCount) remaining=\(axReadGate.occupiedCount) ageMs=\(age) discard=void returned=0")
        }
        if refreshWanted {
            axReadGate.replaceWanted(reconcileAXApplicationIDs())
        }
        var byPID: [pid_t: [ReconcileAXTarget]] = [:]
        for (id, state) in shaded {
            byPID[state.pid, default: []].append(
                ReconcileAXTarget(id: id, pid: state.pid, element: state.element,
                                  needsMinimizedState: state.hide == .minimized,
                                  stamp: foldCallbackStamp(id: id, state: state)))
        }
        let tickets = axReadGate.admit(now: now) { pid in
            guard let stamps = byPID[pid]?.map(\.stamp), !stamps.isEmpty else { return nil }
            return stamps
        }
        guard !tickets.isEmpty else { return }
        for ticket in tickets {
            guard let targets = byPID[ticket.app], !targets.isEmpty else {
                let occupied = axReadGate.occupiedCount
                _ = axReadGate.complete(ticket)
                wlog("reconcile: ax pid=\(ticket.app) elapsedMs=0 occupied=\(occupied) remaining=\(axReadGate.occupiedCount) ageMs=0 discard=absent returned=0")
                continue
            }
            startReconcileAXRead(ticket, targets: targets, reason: reason)
        }
    }

    func startReconcileAXRead(_ ticket: AXReadGate<pid_t, [WS2FoldCallbackStamp]>.Ticket,
                              targets: [ReconcileAXTarget], reason: String) {
        // 每个已准入的 App 自己读自己的窗口。不在这里等待其他 App，也不提前放开名额。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            let snapshots = targets.map { target -> ReconcileAXSnapshot in
                guard let size = axSize(target.element) else {
                    return ReconcileAXSnapshot(stamp: target.stamp, position: nil, size: nil, isMinimized: nil)
                }
                return ReconcileAXSnapshot(stamp: target.stamp, position: axPosition(target.element), size: size,
                    isMinimized: target.needsMinimizedState
                        ? axObservedBoolAttribute(target.element, kAXMinimizedAttribute as String) : nil)
            }
            let endedAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let occupied = self.axReadGate.occupiedCount
                let decision = self.axReadGate.complete(ticket)
                let elapsed = Int((endedAt - startedAt) * 1000)
                let age = endedAt.isFinite && ticket.admittedAt.isFinite
                    ? Int((endedAt - ticket.admittedAt) * 1000) : -1
                let discard: String
                switch decision {
                case .apply:
                    discard = "none"
                    self.applyReconcileAXSnapshots(snapshots, reason: reason, elapsedMilliseconds: elapsed)
                case .discard(_, .resultVoided):
                    discard = "void"
                case .discard(_, .unknownTicket):
                    discard = "unknown"
                case .absent:
                    discard = "absent"
                }
                wlog("reconcile: ax pid=\(ticket.app) elapsedMs=\(elapsed) occupied=\(occupied) remaining=\(self.axReadGate.occupiedCount) ageMs=\(age) discard=\(discard) returned=1")
                self.pumpReconcileAXReads(reason: reason, refreshWanted: false)
            }
        }
    }
    func applyReconcileAXSnapshots(_ snapshots: [ReconcileAXSnapshot],
                                   reason: String, elapsedMilliseconds: Int) {
        if elapsedMilliseconds >= 50 {
            wlog("slow: reconcile-ax reason=\(reason) took \(elapsedMilliseconds)ms windows=\(snapshots.count)")
        }
        guard MainActor.assumeIsolated({ AuthorizationService.shared.lockState() == .unlocked }) else { return }
        // Observe screen membership at application time, not before a possibly slow AX batch.
        let onScreenIDs = currentOnScreenWindowIDs()
        for snapshot in snapshots {
            guard foldCallbackIsCurrent(snapshot.stamp), let state = shaded[snapshot.id] else { continue }
            guard let size = snapshot.size, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else {
                if sourceWindowMissingShouldCleanup(id: snapshot.id, state: state),
                   foldCallbackIsCurrent(snapshot.stamp) {
                    forceCleanup(snapshot.id)
                }
                continue
            }
            reconcileInvalidCounts.removeValue(forKey: snapshot.id)

            if let pos = snapshot.position, pos.x.isFinite, pos.y.isFinite,
               sourceWindowLooksUserVisible(state: state, pos: pos, size: size,
                                            onScreenWindowIDs: onScreenIDs,
                                            sourceIsMinimized: snapshot.isMinimized),
               foldCallbackIsCurrent(snapshot.stamp) {
                if isFocusShelfMember(id: snapshot.id) {
                    revealFocusShelfMemberFromOutside(id: snapshot.id, state: state, reason: "reconcile-\(reason)")
                    continue
                }
                wlog("reconcile: source already visible; cleanup overlay id=\(snapshot.id) app=\(state.appName)")
                forceCleanup(snapshot.id)
                continue
            }

            guard foldCallbackIsCurrent(snapshot.stamp), let overlay = state.overlay else { continue }
            if let overlayID = state.overlayID, !onScreenIDs.contains(overlayID) {
                continue
            }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                applyOverlayPresentation(overlay, bringForward: false)
                if foldCallbackIsCurrent(snapshot.stamp), arrangedOverlayFrames[snapshot.id] == nil {
                    syncRestoreJournal(id: snapshot.id, fromOverlayFrame: newFrame)
                }
                wlog("reconcile: clamped overlay id=\(snapshot.id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
    }
}
