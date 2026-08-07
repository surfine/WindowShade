// 离屏窗口救援：折叠异常退出后的 journal 恢复与广域停车点扫描。
// 扫描在后台队列、写回在主线程；作为 AppDelegate 扩展实现。
//
// 恢复纪律：找到 journal entry → 尝试恢复 → 验证成功 → 才清掉这条 entry。
// 验证失败的 entry 保留到下一轮 rescue 重试，绝不先删线索再恢复。

import Cocoa

extension AppDelegate {
    struct OffscreenRescueAction {
        let id: CGWindowID
        let win: AXUIElement
        let target: CGPoint
        let size: CGSize
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
    func isAtWindowShadeParkingSpot(_ pos: CGPoint) -> Bool {
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

    func collectJournalRescueActions(targetTopLeft: CGPoint,
                                             into result: inout JournalRescueResult) {
        let entries = shadeJournalEntries()
        guard !entries.isEmpty else { return }
        var rescued = 0

        for app in NSWorkspace.shared.runningApplications {
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

                if journalString(entry, "hide") == HideMethod.privateAlpha.rawValue {
                    let alpha = Float(journalNumber(entry, "originalAlpha") ?? 1)
                    result.alphaRestores.append(
                        JournalAlphaRestore(id: id, targetAlpha: max(0.05, min(alpha, 1.0))))
                    wlog("journal: alpha restore queued id=\(id) app=\(journalString(entry, "appName"))")
                    continue
                }

                guard let pos = axPosition(win), let size = axSize(win) else { continue }
                if windowIsVisible(pos: pos, size: size) {
                    // preparing intent 且窗口仍可见：事务没走到隐藏这一步（进程在
                    // 写 intent 后、隐藏前被杀），窗口完好，无需救援，安全清理。
                    if journalString(entry, "stage") == ShadeLifecycleStage.preparing.rawValue {
                        result.resolvedIDs.insert(id)
                        wlog("journal: preparing intent resolved (window visible) id=\(id)")
                    }
                    continue
                }

                let target = CGPoint(
                    x: CGFloat(journalNumber(entry, "originalX") ?? Double(targetTopLeft.x + CGFloat(rescued * 24))),
                    y: CGFloat(journalNumber(entry, "originalY") ?? Double(targetTopLeft.y + CGFloat(rescued * 24)))
                )
                let originalSize = CGSize(
                    width: CGFloat(journalNumber(entry, "originalWidth") ?? Double(size.width)),
                    height: CGFloat(journalNumber(entry, "originalHeight") ?? Double(size.height))
                )
                let safeTarget: CGPoint
                if windowIsVisible(pos: target, size: originalSize) {
                    safeTarget = target
                } else {
                    let frame = cocoaFrame(fromAXPosition: target, size: originalSize)
                    // 优先恢复到折叠时所在显示器，避免多显示器布局变化后救错屏。
                    let displayID = journalNumber(entry, "displayID").map { CGDirectDisplayID($0) }
                    safeTarget = axPosition(fromCocoaFrame: clampedFrame(frame, margin: 16,
                                                                          preferredDisplayID: displayID))
                }
                result.actions.append(OffscreenRescueAction(id: id, win: win,
                                                            target: safeTarget, size: originalSize))
                rescued += 1
                wlog("journal: rescued id=\(id) app=\(journalString(entry, "appName")) target=(\(Int(safeTarget.x)),\(Int(safeTarget.y)))")
            }
        }
    }

    // 每个恢复动作单独验证：geometry 恢复至少确认 AXPosition/AXSize 可重新读取、
    // 窗口落在有效显示区域；只有验证成功的 entry 才允许被清理。
    func rescueActionVerified(_ action: OffscreenRescueAction) -> Bool {
        guard let pos = axPosition(action.win), let size = axSize(action.win) else { return false }
        guard pos.x.isFinite, pos.y.isFinite, size.width > 1, size.height > 1 else { return false }
        return windowIsVisible(pos: pos, size: size)
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
    func collectParkedWindowRescueActions(targetTopLeft: CGPoint,
                                                  into actions: inout [OffscreenRescueAction]) -> Int {
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
    func rescueOffscreenWindows(silent: Bool) {
        guard !isRescuingOffscreenWindows else {
            isRescueQueued = true
            return
        }
        isRescuingOffscreenWindows = true
        // 屏幕几何在主线程取好（NSScreen 只在主线程访问）；AX 扫描在后台。
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            isRescuingOffscreenWindows = false
            if !silent { quietNotice("没有可用屏幕", log: "rescue: no screen") }
            return
        }
        let targetTopLeft = CGPoint(x: screen.visibleFrame.minX + 80,
                                    y: coordinateBaselineY() - (screen.visibleFrame.maxY - 80))
        let finish: (String?) -> Void = { [weak self] notice in
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
                DispatchQueue.main.async { self.showPermissionOnboardingIfNeeded(force: true) }
                finish(silent ? nil : "需要权限")
                return
            }
            var result = JournalRescueResult()
            self.collectJournalRescueActions(targetTopLeft: targetTopLeft, into: &result)
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
                    guard action.id != 0 else {
                        setAXSize(action.win, action.size)
                        setAXPosition(action.win, action.target)
                        raiseAXWindow(action.win)
                        continue
                    }
                    setAXSize(action.win, action.size)
                    setAXPosition(action.win, action.target)
                    raiseAXWindow(action.win)
                    if self.rescueActionVerified(action) {
                        verifiedIDs.insert(action.id)
                        wlog("journal: rescue verified id=\(action.id)")
                    } else {
                        wlog("journal: rescue unverified, keep entry for retry id=\(action.id)")
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
