// 离屏窗口救援：折叠异常退出后的 journal 恢复与广域停车点扫描。
// 扫描在后台队列、写回在主线程；作为 AppDelegate 扩展实现。
//
// 恢复纪律：找到 journal entry → 尝试恢复 → 验证成功 → 才清掉这条 entry。
// 验证失败的 entry 保留到下一轮 rescue 重试，绝不先删线索再恢复。
//
// Swift 6：`AppDelegate` 是 `@MainActor`。后台队列上的扫描绝不能碰主线程隔离
// 的实例方法（否则执行期 `_dispatch_assert_queue_fail` → SIGTRAP）。journal
// 条目在 hop 之前于主线程读好；屏幕夹紧在写回主线程时做。

import Cocoa

extension AppDelegate {
    struct OffscreenRescueAction {
        let id: CGWindowID
        let win: AXUIElement
        let target: CGPoint
        let size: CGSize
        var pid: pid_t? = nil
        var hide: HideMethod? = nil
        var targetAlpha: Float? = nil
        var preferredDisplayID: CGDirectDisplayID? = nil
    }

    struct JournalAlphaRestore {
        let id: CGWindowID
        let targetAlpha: Float
    }

    struct JournalRescueResult {
        var actions: [OffscreenRescueAction] = []
        var alphaRestores: [JournalAlphaRestore] = []
        // preparing intent 且窗口当前可见：事务没有真正走到隐藏，无需救援，
        // 可以直接清理这条 intent（安全，因为窗口本身完好可见）。
        var resolvedIDs: Set<CGWindowID> = []
    }

    // WindowShade 自己的停车点（见 axOffscreenHide / privateSLSOffscreenHide /
    // livePreviewParkingSpots）：主点 (-32000,-32000)，备选 (-12000, y)/
    // (x, -12000)/(-12000,-12000)。判据只匹配这些停车带：
    // - 两轴都在停车带（主点 / (-12000,-12000)），或
    // - 单轴在停车带、另一轴是"像普通窗口坐标"的值（备选点），
    // 避免误救其他 app 自己放到极远坐标（如 -100000）的窗口。
    nonisolated func isAtWindowShadeParkingSpot(_ pos: CGPoint) -> Bool {
        func onParkingBand(_ v: CGFloat) -> Bool {
            abs(v + 12000) <= 96 || abs(v + 32000) <= 96
        }
        func looksLikeWindowAxis(_ v: CGFloat) -> Bool {
            v >= -8000 && v <= 24000
        }
        let xParked = onParkingBand(pos.x)
        let yParked = onParkingBand(pos.y)
        if xParked && yParked { return true }
        return (xParked && looksLikeWindowAxis(pos.y))
            || (yParked && looksLikeWindowAxis(pos.x))
    }

    /// 后台扫描：只吃已快照的 journal，不读 `self` 上的主线程状态。
    nonisolated func collectJournalRescueActions(
        entries: [[String: Any]],
        targetTopLeft: CGPoint,
        into result: inout JournalRescueResult
    ) {
        guard !entries.isEmpty else { return }
        var rescued = 0

        // 与专注同理：救援扫描原本对每个运行中的进程都发一次 AX 枚举，
        // 启动期这条路径直接决定「launch」有多慢。
        let pidsOwningWindows = WindowListCache.shared.pidsWithWindows()

        for app in NSWorkspace.shared.runningApplications {
            guard pidsOwningWindows.contains(app.processIdentifier) else { continue }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let entry = entries.first(where: { entry in
                    guard let id = journalID(entry),
                          !result.resolvedIDs.contains(id),
                          !result.actions.contains(where: { $0.id == id }),
                          !result.alphaRestores.contains(where: { $0.id == id }) else { return false }
                    return journalMatches(entry, app: app, win: win)
                }), let id = journalID(entry) else { continue }

                guard let pos = axPosition(win), let size = axSize(win) else { continue }
                if windowIsVisible(pos: pos, size: size),
                   journalString(entry, "stage") != ShadeLifecycleStage.restoring.rawValue,
                   journalString(entry, "hide") != HideMethod.minimized.rawValue,
                   journalString(entry, "hide") != HideMethod.hidden.rawValue,
                   journalString(entry, "hide") != HideMethod.privateAlpha.rawValue {
                    // preparing intent 且窗口仍可见：事务没走到隐藏这一步（进程在
                    // 写 intent 后、隐藏前被杀），窗口完好，无需救援，安全清理。
                    if journalString(entry, "stage") == ShadeLifecycleStage.preparing.rawValue {
                        result.resolvedIDs.insert(id)
                        wlog("journal: preparing intent resolved (window visible) id=\(id)")
                    }
                    continue
                }

                let fallbackOrigin = CGPoint(
                    x: targetTopLeft.x + CGFloat(rescued * 24),
                    y: targetTopLeft.y + CGFloat(rescued * 24)
                )
                // 坏数字整条隔离：不进 actions、不删 entry，下一轮仍可检查。
                guard let geometry = JournalNumeric.rescueGeometry(
                    entry, fallbackOrigin: fallbackOrigin, fallbackSize: size
                ) else {
                    wlog("journal: skipped corrupt entry id=\(id) app=\(journalString(entry, "appName"))")
                    continue
                }
                var targetAlpha: Float? = nil
                if journalString(entry, "hide") == HideMethod.privateAlpha.rawValue {
                    targetAlpha = geometry.alpha ?? 1
                }
                // 屏幕夹紧留到主线程写回：后台不能碰 NSScreen / MainActor clampedFrame。
                result.actions.append(OffscreenRescueAction(
                    id: id, win: win,
                    target: geometry.origin, size: geometry.size,
                    pid: app.processIdentifier,
                    hide: HideMethod(rawValue: journalString(entry, "hide")),
                    targetAlpha: targetAlpha,
                    preferredDisplayID: geometry.displayID
                ))
                rescued += 1
                wlog("journal: rescued id=\(id) app=\(journalString(entry, "appName")) target=\(JournalNumeric.formatPoint(geometry.origin))")
            }
        }
    }

    // 每个恢复动作单独验证：geometry 恢复至少确认 AXPosition/AXSize 可重新读取、
    // 窗口落在有效显示区域；只有验证成功的 entry 才允许被清理。
    func rescueActionVerified(_ action: OffscreenRescueAction) -> Bool {
        guard let pos = axPosition(action.win), let size = axSize(action.win) else { return false }
        guard pos.x.isFinite, pos.y.isFinite, size.width > 1, size.height > 1 else { return false }
        guard windowIsVisible(pos: pos, size: size), windowID(of: action.win) == action.id,
              let info = cgWindowInfo(action.id), (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              !axBoolAttribute(action.win, kAXMinimizedAttribute as String) else { return false }
        if let alpha = action.targetAlpha {
            guard let actual = PrivateSLSWindowMover.shared.windowAlpha(id: action.id),
                  abs(actual - alpha) < 0.05 else { return false }
        }
        return abs(pos.x - action.target.x) <= 2 && abs(pos.y - action.target.y) <= 2 &&
            abs(size.width - action.size.width) <= 2 && abs(size.height - action.size.height) <= 2
    }

    func alphaRestoreVerified(_ restore: JournalAlphaRestore) -> Bool {
        guard let current = PrivateSLSWindowMover.shared.windowAlpha(id: restore.id) else { return false }
        return current >= 0.5 || abs(current - restore.targetAlpha) <= 0.15
    }

    func pruneRescuedJournalEntries(rescuedIDs: Set<CGWindowID>) {
        guard !rescuedIDs.isEmpty else { return }
        let entries = shadeJournalEntries()
        let filtered = entries.filter { entry in
            guard let id = journalID(entry) else { return false }
            return !rescuedIDs.contains(id)
        }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: pruned \(entries.count - filtered.count) rescued entries")
        }
    }

    nonisolated func collectParkedWindowRescueActions(
        targetTopLeft: CGPoint,
        into actions: inout [OffscreenRescueAction]
    ) -> Int {
        let allWindows = WindowListCache.shared.allWindows()
        var parkedPIDs: Set<pid_t> = []
        for info in allWindows {
            guard let bounds = cgWindowBounds(info),
                  isAtWindowShadeParkingSpot(CGPoint(x: bounds.minX, y: bounds.minY)),
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            parkedPIDs.insert(owner.int32Value)
        }

        var rescued = 0
        for pid in parkedPIDs {
            let appEl = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let pos = axPosition(win), let size = axSize(win) else { continue }
                // 只救我们自己的停车点附近、且确实不在任何屏幕可见区的窗口。
                guard isAtWindowShadeParkingSpot(pos) else { continue }
                guard !windowIsVisible(pos: pos, size: size) else { continue }
                actions.append(OffscreenRescueAction(
                    id: 0,
                    win: win,
                    target: CGPoint(x: targetTopLeft.x + CGFloat(rescued * 24),
                                    y: targetTopLeft.y + CGFloat(rescued * 24)),
                    size: size))
                rescued += 1
            }
        }
        return rescued
    }

    /// 写回前把 journal 坐标夹进可见屏（主线程；可安全用 NSScreen）。
    func clampedRescueTarget(for action: OffscreenRescueAction) -> CGPoint {
        let frame = cocoaFrame(fromAXPosition: action.target, size: action.size)
        if windowIsVisible(pos: action.target, size: action.size) {
            return action.target
        }
        return axPosition(fromCocoaFrame: clampedFrame(frame, margin: 16,
                                                       preferredDisplayID: action.preferredDisplayID))
    }

    func rescueOffscreenWindows(silent: Bool) {
        guard !isRescuingOffscreenWindows else {
            isRescueQueued = true
            return
        }
        isRescuingOffscreenWindows = true
        // 屏幕几何与 journal 快照都在主线程取好；AX 扫描在后台。
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            isRescuingOffscreenWindows = false
            if !silent { quietNotice("没有可用屏幕", log: "rescue: no screen") }
            return
        }
        let targetTopLeft = CGPoint(x: screen.visibleFrame.minX + 80,
                                    y: coordinateBaselineY() - (screen.visibleFrame.maxY - 80))
        let journalEntries = shadeJournalEntries()
        let finish: @Sendable (String?) -> Void = { [weak self] notice in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRescuingOffscreenWindows = false
                if let notice {
                    self.quietNotice(notice, log: "rescue: \(notice)")
                }
                if self.isRescueQueued {
                    self.isRescueQueued = false
                    self.rescueOffscreenWindows(silent: true)
                }
            }
        }
        rescueWorkQueue.async { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { [weak self] in
                    self?.showPermissionOnboardingIfNeeded(force: true)
                }
                finish(silent ? nil : "需要权限")
                return
            }
            var result = JournalRescueResult()
            // nonisolated 扫描：可从救援队列碰 self，不会踩 MainActor 执行期断言。
            self.collectJournalRescueActions(entries: journalEntries, targetTopLeft: targetTopLeft, into: &result)
            var rescued = result.actions.count + result.alphaRestores.count
            if rescued == 0 {
                rescued += self.collectParkedWindowRescueActions(targetTopLeft: targetTopLeft,
                                                                into: &result.actions)
            }
            // 写回统一在主线程：若扫描期间用户折了窗口（shaded 非空），放弃这批
            // 写回，避免把刚停车的窗口又挪回可见区；journal 清理也回主线程写，
            // 避免与 shade 的 journal 写入竞争。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.shaded.isEmpty {
                    wlog("rescue: shaded windows appeared during scan; skip applying \(result.actions.count) actions")
                    finish(nil)
                    return
                }
                self.pruneShadeJournal(reason: "rescue")
                // 先恢复、逐条验证，再清理：验证失败的 entry 保留，下一轮重试。
                var verifiedIDs = result.resolvedIDs
                for action in result.actions {
                    let target = action.id == 0 ? action.target : self.clampedRescueTarget(for: action)
                    let applied = OffscreenRescueAction(
                        id: action.id, win: action.win, target: target, size: action.size,
                        pid: action.pid, hide: action.hide, targetAlpha: action.targetAlpha,
                        preferredDisplayID: action.preferredDisplayID
                    )
                    guard applied.id != 0 else {
                        setAXSize(applied.win, applied.size)
                        setAXPosition(applied.win, applied.target)
                        raiseAXWindow(applied.win)
                        continue
                    }
                    if let alpha = applied.targetAlpha {
                        _ = PrivateSLSWindowMover.shared.setAlpha(id: applied.id, alpha: alpha)
                    }
                    if applied.hide == .hidden, let pid = applied.pid {
                        _ = NSRunningApplication(processIdentifier: pid)?.unhide()
                    }
                    if applied.hide == .minimized { setAXMinimized(applied.win, false) }
                    setAXSize(applied.win, applied.size)
                    setAXPosition(applied.win, applied.target)
                    raiseAXWindow(applied.win)
                    if self.rescueActionVerified(applied) {
                        verifiedIDs.insert(applied.id)
                        wlog("journal: rescue verified id=\(applied.id)")
                    } else {
                        wlog("journal: rescue unverified, keep entry for retry id=\(applied.id)")
                    }
                }
                for restore in result.alphaRestores {
                    if PrivateSLSWindowMover.shared.setAlpha(id: restore.id, alpha: restore.targetAlpha),
                       self.alphaRestoreVerified(restore) {
                        verifiedIDs.insert(restore.id)
                        wlog("journal: alpha rescue verified id=\(restore.id)")
                    } else {
                        wlog("journal: alpha rescue unverified, keep entry for retry id=\(restore.id)")
                    }
                }
                self.pruneRescuedJournalEntries(rescuedIDs: verifiedIDs)
                wlog("rescueOffscreenWindows: rescued=\(rescued)")
                finish(rescued == 0 && !silent ? "没有需要救援的窗口" : nil)
            }
        }
    }
}
