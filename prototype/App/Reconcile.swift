// 折叠会话监控（Reconcile）：周期性核对真实窗口与卷帘条状态，
// 处理外部唤回、窗口丢失与异常清理。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func updateReconcileTimer() {
        syncReconcileWatches()
        let shouldRun = !shaded.isEmpty || !shadeJournalEntries().isEmpty
        if shouldRun {
            guard reconcileTimer == nil else { return }
            reconcileTimer = MainTimer.repeating(
                interval: shadedWindowReconcileInterval, tolerance: 1.5) { [weak self] in
                self?.reconcileShadedWindows(reason: "timer")
            }
            wlog("reconcile: timer started")
        } else if let timer = reconcileTimer {
            timer.invalidate()
            reconcileTimer = nil
            lastJournalRescueAttempt = nil
            wlog("reconcile: timer stopped")
        }
    }
    /// 让订阅集合和收起的窗口一致。订阅在 hub 上很便宜（只有被盯的窗口才收 SkyLight 事件）。
    /// 退回模式（SkyLight 不可用）下 hub 按 5 秒查，和定时巡检同一个节奏。
    func syncReconcileWatches() {
        MainActor.assumeIsolated {
            for id in Array(reconcileWatches.keys) where shaded[id] == nil {
                reconcileWatches[id]?.cancel()
                reconcileWatches[id] = nil
            }
            for id in shaded.keys where reconcileWatches[id] == nil {
                reconcileWatches[id] = WindowStateHub.shared.watch(id, fallbackInterval: shadedWindowReconcileInterval, ownPolling: true) {
                    [weak self] change, _ in
                    self?.shadedSourceChanged(id, change: change)
                }
            }
        }
    }

    /// 收起的源窗口出了变化：只会让反应更快，定时巡检照旧。
    /// 挪动/出现/样式变 → 排一轮核对（同一阵合成一次，两轮之间至少隔 1 秒）；窗口没了 → 同样只提前排一轮
    /// 普通核对，收不收卷帘条仍由巡检里的孤儿判据决定（AX 读不到尺寸、连续两轮定时巡检、实时查询为空），
    /// 不在这里直接收：sourceWindowID 对有些 App 是按外框/标题配出来的，单凭“这个号没了”可能收错窗口。
    private func shadedSourceChanged(_ id: CGWindowID, change: WindowChange) {
        guard let state = shaded[id] else { return }
        switch ReconcileEventPolicy.reaction(for: change) {
        case .ignore:
            return
        case .reconcile:
            // 我们自己刚收起/刚挪动的那阵子，App 的动静不算唤回（和巡检里同一道忽略期）。
            guard Date() >= state.ignoreAppRevealUntil else { return }
            queueEventReconcile()
        case .recheck:
            queueEventReconcile()
        }
    }

    private func queueEventReconcile() {
        guard !reconcileEventQueued else { return }
        reconcileEventQueued = true
        let elapsed = ProcessInfo.processInfo.systemUptime - lastEventReconcileAt
        MainTimer.fire(after: ReconcileEventPolicy.delay(sinceLastRun: elapsed), tolerance: 0) { [weak self] in
            guard let self else { return }
            self.reconcileEventQueued = false
            self.lastEventReconcileAt = ProcessInfo.processInfo.systemUptime
            guard !self.shaded.isEmpty else { return }
            self.reconcileShadedWindows(reason: "event")
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
        case .cornerParked:
            // 角落停放只留 1 像素：不是用户把窗口叫回来了。
            return false
        case .offscreen:
            return Date() >= state.ignoreAppRevealUntil
        case .privateOffscreen:
            // 停车是窗口服务器做的：AX 坐标与 kCGWindowIsOnscreen 都不跟着更新，只有外框
            // 才说明它停好没有。外框仍与某块屏相交，才算它看起来回来了（见 round2 F7）。
            guard cgWindowIsVisible(id: state.sourceWindowID, fallbackSize: size) == false else { return false }
            return Date() >= state.ignoreAppRevealUntil
        case .privateAlpha:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            let sampledAlpha = PrivateSLSWindowMover.shared.windowAlpha(id: state.sourceWindowID)
                ?? (cgWindowInfo(state.sourceWindowID)?[kCGWindowAlpha as String] as? NSNumber).map(\.floatValue)
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
            guard sourceIsMinimized == false else { return false }
            // 收起刚装好、隐藏还没被验证的那一会儿不判「回来了」：台前调度把最小化做成
            // 往侧条缩的动画，动画途中外框还是大窗、也不在侧条带上（见 FoldVerifier 的迟到观察窗）。
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            // 停在台前调度侧条里的卡片外框也算“在屏上”，但用户没把它叫回来（规格 R19）。
            return !windowParkedInStageStrip(id: state.sourceWindowID, axSize: size)
        case .ownWindowOrderedOut:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            return ownWindow(id: state.sourceWindowID)?.isVisible ?? false
        }
    }
    func shouldLogReconcileInvalidCount(_ count: Int) -> Bool {
        count == 1 || count == 3 || count == 10 || count % 60 == 0
    }
    /// 连续几轮查不到窗口才算孤儿（每轮间隔见 shadedWindowReconcileInterval）。
    var orphanStripConfirmRounds: Int { 2 }
    func sourceWindowMissingShouldCleanup(id: CGWindowID, state: ShadeState) -> Bool {
        guard runningApp(pid: state.pid) != nil else {
            wlog("reconcile: source app gone id=\(id) app=\(state.appName)")
            return true
        }

        let count = (reconcileInvalidCounts[id] ?? 0) + 1
        reconcileInvalidCounts[id] = count

        // 孤儿卷帘条（规格 R10）：App 还在，但窗口服务器已经查不到这扇窗——隐藏、最小化、移到屏外的窗口
        // 都还查得到，查不到只能是被关掉了。窗口编号不会复用回来，连续两轮（约 10 秒）都查不到才收掉卷帘条。
        // 和销毁通知那条路一样严格：查询本身成功、且结果为空，才算查不到（FoldTransaction.handleAXNotification）。
        // 那条路只在通知到达时查一次；通知丢了或窗口服务器还没删干净，就靠这里兜底。
        // 快速查看的收起本来就是把窗口关掉（.quickLookClosed），不算孤儿。
        if count >= orphanStripConfirmRounds, state.hide != .quickLookClosed,
           let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, state.sourceWindowID) as? [[String: Any]],
           windows.isEmpty {
            wlog("reconcile: orphan strip id=\(id) app=\(state.appName) hide=\(state.hide.rawValue) count=\(count); window closed elsewhere, closing strip")
            return true
        }

        switch state.hide {
        case .hidden, .minimized, .offscreen, .privateOffscreen, .privateAlpha, .cornerParked, .ownWindowOrderedOut, .quickLookClosed:
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

        if ReconcileEventPolicy.countsTowardMissing(reason: reason) {
            reconcileScheduledPIDs.formUnion(shaded.values.map(\.pid))
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
                // 正常的一次读（几毫秒、结果被采用）每 5 秒每个收起的 App 一次，只写慢的和被丢弃的。
                if elapsed >= 50 || discard != "none" {
                    wlog("reconcile: ax pid=\(ticket.app) elapsedMs=\(elapsed) occupied=\(occupied) remaining=\(self.axReadGate.occupiedCount) ageMs=\(age) discard=\(discard) returned=1")
                }
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
        // 这批是哪个 App 的：巡检要过它，这次读数就按巡检算，并且只算一次。
        let scheduled = Set(snapshots.compactMap { shaded[$0.id]?.pid }).intersection(reconcileScheduledPIDs)
        reconcileScheduledPIDs.subtract(scheduled)
        for snapshot in snapshots {
            guard foldCallbackIsCurrent(snapshot.stamp), let state = shaded[snapshot.id] else { continue }
            guard let size = snapshot.size, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else {
                guard ReconcileEventPolicy.countsTowardMissing(reason: reason, scheduledPassPending: scheduled.contains(state.pid)) else { continue }
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
            // 卷帘条本来就贴在那扇窗的标题栏上，顶到屏幕边是它的正常位置：
            // 留 8 点边距会把它从 (0,1041) 压成 (215,1033)，既离开标题栏，又把恢复位置也带跑。
            let newFrame = clampedFrame(oldFrame, margin: 0, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                applyOverlayPresentation(overlay, bringForward: false)
                if foldCallbackIsCurrent(snapshot.stamp), arrangedOverlayFrames[snapshot.id] == nil {
                    syncRestoreJournal(id: snapshot.id, fromOverlayFrame: newFrame, reason: "reconcile-clamp")
                }
                wlog("reconcile: clamped overlay id=\(snapshot.id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
    }
}
