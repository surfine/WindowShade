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
            let alpha = PrivateSLSWindowMover.shared.windowAlpha(id: state.sourceWindowID)
                ?? Float((cgWindowInfo(state.sourceWindowID)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            return alpha > 0.05
        case .hidden:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            guard let app = runningApp(pid: state.pid) else { return true }
            return !app.isHidden
        case .minimized:
            // AX 快照读取在 reconcileAXWorkQueue；没有快照时保守地认为仍不可见，
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
            let shouldCleanup = count >= 3
            if shouldCleanup {
                wlog("reconcile: source invalid repeatedly id=\(id) app=\(state.appName) count=\(count)")
            }
            return shouldCleanup
        }
    }
    func reconcileShadedWindows(reason: String) {
        guard !isReconcilingShadedWindows else { return }
        isReconcilingShadedWindows = true

        pruneShadeJournal(reason: "reconcile-\(reason)")

        guard AXIsProcessTrusted() else {
            finishReconcileShadedWindows()
            return
        }
        if eventTap == nil, setupEventTap() {
            wlog("reconcile: event tap restored")
        }

        let now = Date()
        if shaded.isEmpty {
            if shouldRetryJournalRescue(now: now) {
                lastJournalRescueAttempt = now
                rescueOffscreenWindows(silent: true)
            }
            finishReconcileShadedWindows()
            return
        }

        let onScreenIDs = currentOnScreenWindowIDs()
        let targets = shaded.map { id, state in
            ReconcileAXTarget(id: id, pid: state.pid, element: state.element,
                              needsMinimizedState: state.hide == .minimized)
        }
        reconcileAXWorkQueue.async { [weak self] in
            let startedAt = CFAbsoluteTimeGetCurrent()
            // 按 app 分组：不同 app 的 AX IPC 互不阻塞，可以并行采集；同 app 的
            // 窗口串行读取，避免对忙 app 并发轰炸。忙 app 单次 2s 超时不再拖住
            // 其他 app 的快照（旧实现串行累加，3 个忙 app 就是 6s+）。
            let grouped = Dictionary(grouping: targets, by: { $0.pid })
            let group = DispatchGroup()
            let resultLock = NSLock()
            var snapshots: [ReconcileAXSnapshot] = []
            for pidTargets in grouped.values {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let local = pidTargets.map { target -> ReconcileAXSnapshot in
                        guard let size = axSize(target.element) else {
                            return ReconcileAXSnapshot(id: target.id, position: nil,
                                                       size: nil, isMinimized: nil)
                        }
                        return ReconcileAXSnapshot(id: target.id,
                                                   position: axPosition(target.element),
                                                   size: size,
                                                   isMinimized: target.needsMinimizedState
                                                       ? axBoolAttribute(target.element, kAXMinimizedAttribute as String)
                                                       : nil)
                    }
                    resultLock.lock()
                    snapshots.append(contentsOf: local)
                    resultLock.unlock()
                    group.leave()
                }
            }
            group.wait()
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            DispatchQueue.main.async { [weak self] in
                self?.applyReconcileAXSnapshots(snapshots, onScreenIDs: onScreenIDs,
                                                reason: reason, elapsedMilliseconds: elapsedMilliseconds)
            }
        }
    }
    func applyReconcileAXSnapshots(_ snapshots: [ReconcileAXSnapshot], onScreenIDs: Set<CGWindowID>,
                                           reason: String, elapsedMilliseconds: Int) {
        defer { finishReconcileShadedWindows() }
        if elapsedMilliseconds >= 50 {
            wlog("slow: reconcile-ax reason=\(reason) took \(elapsedMilliseconds)ms windows=\(snapshots.count)")
        }
        for snapshot in snapshots {
            // 异步 AX 读取期间用户可能已展开/关闭窗口，只按仍存在的当前 state 应用。
            guard let state = shaded[snapshot.id] else { continue }
            guard let size = snapshot.size else {
                if sourceWindowMissingShouldCleanup(id: snapshot.id, state: state) {
                    forceCleanup(snapshot.id)
                }
                continue
            }
            reconcileInvalidCounts.removeValue(forKey: snapshot.id)

            if let pos = snapshot.position,
               sourceWindowLooksUserVisible(state: state, pos: pos, size: size,
                                            onScreenWindowIDs: onScreenIDs,
                                            sourceIsMinimized: snapshot.isMinimized) {
                if isFocusShelfMember(id: snapshot.id) {
                    revealFocusShelfMemberFromOutside(id: snapshot.id, state: state, reason: "reconcile-\(reason)")
                    continue
                }
                wlog("reconcile: source already visible; cleanup overlay id=\(snapshot.id) app=\(state.appName)")
                forceCleanup(snapshot.id)
                continue
            }

            guard let overlay = state.overlay else { continue }
            if let overlayID = state.overlayID, !onScreenIDs.contains(overlayID) {
                continue
            }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                applyOverlayPresentation(overlay, bringForward: false)
                if arrangedOverlayFrames[snapshot.id] == nil {
                    syncRestoreJournal(id: snapshot.id, fromOverlayFrame: newFrame)
                }
                wlog("reconcile: clamped overlay id=\(snapshot.id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
    }
    func finishReconcileShadedWindows() {
        isReconcilingShadedWindows = false
        updateReconcileTimer()
    }
}
